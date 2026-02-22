defmodule JidoStudio.Persistence.ETS do
  @moduledoc false
  use GenServer

  @behaviour JidoStudio.Persistence.Adapter

  @docs_table :jido_studio_persistence_docs
  @events_table :jido_studio_persistence_events
  @seq_table :jido_studio_persistence_event_seq

  @default_event_retention 10_000
  @default_read_limit 200

  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :permanent,
      shutdown: 5_000
    }
  end

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    ensure_tables()

    retention =
      opts
      |> Keyword.get(
        :event_retention,
        Application.get_env(:jido_studio, :persistence_event_retention, @default_event_retention)
      )
      |> normalize_positive_integer(@default_event_retention)

    seq_by_stream =
      :ets.tab2list(@seq_table)
      |> Map.new(fn {stream, seq} -> {stream, seq} end)

    {:ok, %{event_retention: retention, seq_by_stream: seq_by_stream}}
  end

  @impl true
  def put_doc(namespace, id, doc, _opts) when is_map(doc) do
    with :ok <- ensure_started() do
      ns = normalize_namespace(namespace)
      doc_id = normalize_id(id)
      now = now_ms()

      normalized =
        doc
        |> Map.put(:id, doc_id)
        |> Map.put_new(:inserted_at, now)
        |> Map.put(:updated_at, now)

      :ets.insert(@docs_table, {{ns, doc_id}, normalized})
      :ok
    end
  end

  def put_doc(_namespace, _id, _doc, _opts), do: {:error, :invalid_doc}

  @impl true
  def get_doc(namespace, id, _opts) do
    with :ok <- ensure_started() do
      ns = normalize_namespace(namespace)
      doc_id = normalize_id(id)

      case :ets.lookup(@docs_table, {ns, doc_id}) do
        [{{^ns, ^doc_id}, doc}] -> {:ok, doc}
        [] -> :not_found
      end
    end
  end

  @impl true
  def list_docs(namespace, opts) do
    case ensure_started() do
      :ok ->
        ns = normalize_namespace(namespace)
        id_prefix = normalize_optional_string(Keyword.get(opts, :id_prefix))
        order = normalize_order(Keyword.get(opts, :order, :desc))
        sort_by = Keyword.get(opts, :sort_by, :updated_at)

        limit =
          normalize_non_negative_integer(
            Keyword.get(opts, :limit, @default_read_limit),
            @default_read_limit
          )

        offset = normalize_non_negative_integer(Keyword.get(opts, :offset, 0), 0)

        @docs_table
        |> :ets.tab2list()
        |> Enum.reduce([], fn
          {{^ns, doc_id}, doc}, acc ->
            if is_nil(id_prefix) or String.starts_with?(doc_id, id_prefix) do
              [doc | acc]
            else
              acc
            end

          _, acc ->
            acc
        end)
        |> Enum.sort_by(&sort_value(&1, sort_by), order)
        |> Enum.drop(offset)
        |> maybe_take(limit)

      {:error, _reason} ->
        []
    end
  end

  @impl true
  def delete_doc(namespace, id, _opts) do
    with :ok <- ensure_started() do
      ns = normalize_namespace(namespace)
      doc_id = normalize_id(id)
      :ets.delete(@docs_table, {ns, doc_id})
      :ok
    end
  end

  @impl true
  def append_event(stream, event, opts) when is_binary(stream) and is_map(event) do
    with :ok <- ensure_started() do
      timeout = normalize_positive_integer(Keyword.get(opts, :timeout, 5_000), 5_000)
      GenServer.call(__MODULE__, {:append_event, stream, event}, timeout)
    end
  end

  def append_event(_stream, _event, _opts), do: {:error, :invalid_event}

  @impl true
  def read_events(stream, opts) when is_binary(stream) do
    case ensure_started() do
      :ok ->
        order = normalize_order(Keyword.get(opts, :order, :asc))

        limit =
          normalize_non_negative_integer(
            Keyword.get(opts, :limit, @default_read_limit),
            @default_read_limit
          )

        offset = normalize_non_negative_integer(Keyword.get(opts, :offset, 0), 0)
        after_seq = normalize_optional_integer(Keyword.get(opts, :after_seq))
        before_seq = normalize_optional_integer(Keyword.get(opts, :before_seq))

        @events_table
        |> :ets.tab2list()
        |> Enum.reduce([], fn
          {{^stream, seq}, event}, acc ->
            if seq_in_range?(seq, after_seq, before_seq) do
              [event | acc]
            else
              acc
            end

          _, acc ->
            acc
        end)
        |> Enum.sort_by(&Map.get(&1, :seq, 0), order)
        |> Enum.drop(offset)
        |> maybe_take(limit)

      {:error, _reason} ->
        []
    end
  end

  def read_events(_stream, _opts), do: []

  @impl true
  def handle_call({:append_event, stream, event}, _from, state) do
    seq =
      case :ets.lookup(@seq_table, stream) do
        [{^stream, current}] when is_integer(current) and current >= 0 ->
          current + 1

        _ ->
          max_stream_seq(stream) + 1
      end

    now = now_ms()

    normalized_event =
      event
      |> Map.put(:stream, stream)
      |> Map.put(:seq, seq)
      |> Map.put_new(:inserted_at, now)

    :ets.insert(@events_table, {{stream, seq}, normalized_event})
    :ets.insert(@seq_table, {stream, seq})

    if seq > state.event_retention do
      prune_key = {stream, seq - state.event_retention}
      :ets.delete(@events_table, prune_key)
    end

    {:reply, {:ok, normalized_event},
     %{state | seq_by_stream: Map.put(state.seq_by_stream, stream, seq)}}
  end

  defp ensure_started do
    case Process.whereis(__MODULE__) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case start_link([]) do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp ensure_tables do
    ensure_table(@docs_table, [:set, :named_table, :public, read_concurrency: true])

    ensure_table(@events_table, [
      :ordered_set,
      :named_table,
      :public,
      read_concurrency: true,
      write_concurrency: true
    ])

    ensure_table(@seq_table, [:set, :named_table, :public])
  end

  defp ensure_table(table, options) do
    case :ets.info(table) do
      :undefined ->
        :ets.new(table, options)
        :ok

      _ ->
        :ok
    end
  rescue
    _ -> :ok
  end

  defp normalize_namespace(namespace) when is_atom(namespace), do: Atom.to_string(namespace)
  defp normalize_namespace(namespace) when is_binary(namespace), do: namespace
  defp normalize_namespace(namespace), do: to_string(namespace)

  defp normalize_id(id) when is_binary(id), do: id
  defp normalize_id(id) when is_atom(id), do: Atom.to_string(id)
  defp normalize_id(id), do: to_string(id)

  defp normalize_optional_string(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_string(_), do: nil

  defp normalize_optional_integer(value) when is_integer(value), do: value
  defp normalize_optional_integer(_), do: nil

  defp normalize_positive_integer(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_positive_integer(_value, default), do: default

  defp normalize_non_negative_integer(value, _default) when is_integer(value) and value >= 0,
    do: value

  defp normalize_non_negative_integer(_value, default), do: default

  defp normalize_order(:asc), do: :asc
  defp normalize_order(:desc), do: :desc
  defp normalize_order(_), do: :desc

  defp sort_value(doc, key) when is_map(doc) do
    Map.get(doc, key, Map.get(doc, :updated_at, 0))
  end

  defp sort_value(_, _), do: 0

  defp maybe_take(list, 0), do: list
  defp maybe_take(list, limit), do: Enum.take(list, limit)

  defp seq_in_range?(seq, after_seq, before_seq) when is_integer(seq) do
    after_ok = is_nil(after_seq) or seq > after_seq
    before_ok = is_nil(before_seq) or seq < before_seq
    after_ok and before_ok
  end

  defp seq_in_range?(_, _, _), do: false

  defp max_stream_seq(stream) when is_binary(stream) do
    @events_table
    |> :ets.match({{stream, :"$1"}, :_})
    |> Enum.reduce(0, fn
      [seq], acc when is_integer(seq) and seq > acc -> seq
      _other, acc -> acc
    end)
  end

  defp max_stream_seq(_), do: 0

  defp now_ms, do: System.system_time(:millisecond)
end
