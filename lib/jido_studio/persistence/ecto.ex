defmodule JidoStudio.Persistence.Ecto do
  @moduledoc false

  @behaviour JidoStudio.Persistence.Adapter

  @default_docs_table "jido_studio_docs"
  @default_events_table "jido_studio_events"
  @default_read_limit 200

  @impl true
  def put_doc(namespace, id, doc, opts) when is_map(doc) do
    with {:ok, repo, query_opts, docs_table, _events_table} <- resolve(opts),
         {:ok, json_doc} <- encode_json(doc),
         {:ok, _result} <-
           query(
             repo,
             """
             INSERT INTO #{docs_table} (namespace, doc_id, data, inserted_at, updated_at)
             VALUES ($1, $2, $3::jsonb, NOW(), NOW())
             ON CONFLICT (namespace, doc_id)
             DO UPDATE SET data = EXCLUDED.data, updated_at = NOW()
             """,
             [to_string(namespace), to_string(id), json_doc],
             query_opts
           ) do
      :ok
    end
  end

  def put_doc(_namespace, _id, _doc, _opts), do: {:error, :invalid_doc}

  @impl true
  def get_doc(namespace, id, opts) do
    with {:ok, repo, query_opts, docs_table, _events_table} <- resolve(opts),
         {:ok, result} <-
           query(
             repo,
             "SELECT data FROM #{docs_table} WHERE namespace = $1 AND doc_id = $2 LIMIT 1",
             [to_string(namespace), to_string(id)],
             query_opts
           ) do
      case Map.get(result, :rows, []) do
        [[data]] -> decode_json_result(data)
        _ -> :not_found
      end
    end
  end

  @impl true
  def list_docs(namespace, opts) do
    with {:ok, repo, query_opts, docs_table, _events_table} <- resolve(opts),
         {:ok, {sql, params}} <- docs_list_query(docs_table, namespace, opts),
         {:ok, result} <- query(repo, sql, params, query_opts) do
      rows_to_docs(result)
    else
      _ -> []
    end
  end

  @impl true
  def delete_doc(namespace, id, opts) do
    with {:ok, repo, query_opts, docs_table, _events_table} <- resolve(opts),
         {:ok, _result} <-
           query(
             repo,
             "DELETE FROM #{docs_table} WHERE namespace = $1 AND doc_id = $2",
             [to_string(namespace), to_string(id)],
             query_opts
           ) do
      :ok
    end
  end

  @impl true
  def append_event(stream, event, opts) when is_binary(stream) and is_map(event) do
    with {:ok, repo, query_opts, _docs_table, events_table} <- resolve(opts),
         {:ok, json_event} <- encode_json(event),
         {:ok, result} <-
           query(
             repo,
             """
             INSERT INTO #{events_table} (stream, event, inserted_at)
             VALUES ($1, $2::jsonb, NOW())
             RETURNING seq
             """,
             [stream, json_event],
             query_opts
           ) do
      case Map.get(result, :rows, []) do
        [[seq]] -> {:ok, Map.put(event, :seq, seq)}
        _ -> {:error, :missing_sequence}
      end
    end
  end

  def append_event(_stream, _event, _opts), do: {:error, :invalid_event}

  @impl true
  def read_events(stream, opts) when is_binary(stream) do
    with {:ok, repo, query_opts, _docs_table, events_table} <- resolve(opts),
         {:ok, {sql, params}} <- events_read_query(events_table, stream, opts),
         {:ok, result} <- query(repo, sql, params, query_opts) do
      rows_to_events(result)
    else
      _ -> []
    end
  end

  def read_events(_stream, _opts), do: []

  defp resolve(opts) do
    repo = Keyword.get(opts, :repo)

    docs_table =
      opts
      |> Keyword.get(:docs_table, @default_docs_table)
      |> normalize_identifier(@default_docs_table)

    events_table =
      opts
      |> Keyword.get(:events_table, @default_events_table)
      |> normalize_identifier(@default_events_table)

    query_opts =
      []
      |> maybe_put_prefix(Keyword.get(opts, :prefix))
      |> Keyword.put_new(:timeout, 15_000)

    cond do
      is_nil(repo) ->
        {:error, :missing_repo}

      not is_atom(repo) ->
        {:error, :invalid_repo}

      true ->
        {:ok, repo, query_opts, docs_table, events_table}
    end
  end

  defp docs_list_query(docs_table, namespace, opts) do
    order = normalize_order(Keyword.get(opts, :order, :desc))

    limit =
      normalize_non_negative_integer(
        Keyword.get(opts, :limit, @default_read_limit),
        @default_read_limit
      )

    offset = normalize_non_negative_integer(Keyword.get(opts, :offset, 0), 0)
    id_prefix = normalize_optional_string(Keyword.get(opts, :id_prefix))

    {sql, params} =
      if is_binary(id_prefix) do
        {
          """
          SELECT doc_id, data
          FROM #{docs_table}
          WHERE namespace = $1 AND doc_id LIKE $2
          ORDER BY updated_at #{order}
          LIMIT $3 OFFSET $4
          """,
          [to_string(namespace), "#{id_prefix}%", limit, offset]
        }
      else
        {
          """
          SELECT doc_id, data
          FROM #{docs_table}
          WHERE namespace = $1
          ORDER BY updated_at #{order}
          LIMIT $2 OFFSET $3
          """,
          [to_string(namespace), limit, offset]
        }
      end

    {:ok, {sql, params}}
  end

  defp events_read_query(events_table, stream, opts) do
    order = normalize_order(Keyword.get(opts, :order, :asc))

    limit =
      normalize_non_negative_integer(
        Keyword.get(opts, :limit, @default_read_limit),
        @default_read_limit
      )

    offset = normalize_non_negative_integer(Keyword.get(opts, :offset, 0), 0)
    after_seq = normalize_optional_integer(Keyword.get(opts, :after_seq))
    before_seq = normalize_optional_integer(Keyword.get(opts, :before_seq))

    conditions =
      []
      |> maybe_add_condition("seq >", after_seq)
      |> maybe_add_condition("seq <", before_seq)

    base = "SELECT seq, event FROM #{events_table} WHERE stream = $1"

    {where_sql, where_params} =
      Enum.reduce(Enum.with_index(conditions, 2), {"", [stream]}, fn {{op, value}, idx},
                                                                     {acc_sql, acc_params} ->
        clause = " AND #{op} $#{idx}"
        {acc_sql <> clause, acc_params ++ [value]}
      end)

    final_sql =
      base <>
        where_sql <>
        " ORDER BY seq #{order} LIMIT $#{length(where_params) + 1} OFFSET $#{length(where_params) + 2}"

    {:ok, {final_sql, where_params ++ [limit, offset]}}
  end

  defp maybe_add_condition(acc, _op, nil), do: acc
  defp maybe_add_condition(acc, op, value), do: acc ++ [{op, value}]

  defp query(repo, sql, params, opts) do
    sql_module = Module.concat([Ecto, Adapters, SQL])

    cond do
      not Code.ensure_loaded?(sql_module) ->
        {:error, :ecto_sql_not_available}

      not function_exported?(sql_module, :query, 4) ->
        {:error, :ecto_sql_not_available}

      true ->
        case apply(sql_module, :query, [repo, sql, params, opts]) do
          {:ok, result} -> {:ok, result}
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp rows_to_docs(result) do
    result
    |> Map.get(:rows, [])
    |> Enum.map(fn
      [doc_id, data] ->
        case decode_json_result(data) do
          {:ok, doc} -> Map.put(doc, :id, doc_id)
          {:error, _} -> %{id: doc_id, raw: data}
        end

      _ ->
        %{}
    end)
  end

  defp rows_to_events(result) do
    result
    |> Map.get(:rows, [])
    |> Enum.map(fn
      [seq, data] ->
        case decode_json_result(data) do
          {:ok, event} -> Map.put(event, :seq, seq)
          _ -> %{seq: seq, raw: data}
        end

      _ ->
        %{}
    end)
  end

  defp decode_json_result(data) when is_map(data), do: {:ok, data}

  defp decode_json_result(data) when is_binary(data) do
    case Jason.decode(data) do
      {:ok, decoded} when is_map(decoded) -> {:ok, decoded}
      {:ok, _decoded} -> {:error, :invalid_json}
      {:error, reason} -> {:error, reason}
    end
  end

  defp decode_json_result(_), do: {:error, :invalid_json}

  defp encode_json(map) when is_map(map) do
    case Jason.encode(map) do
      {:ok, json} -> {:ok, json}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_identifier(value, fallback) when is_binary(value) do
    if Regex.match?(~r/^[a-zA-Z_][a-zA-Z0-9_]*$/, value), do: value, else: fallback
  end

  defp normalize_identifier(_, fallback), do: fallback

  defp normalize_non_negative_integer(value, _default) when is_integer(value) and value >= 0,
    do: value

  defp normalize_non_negative_integer(_value, default), do: default

  defp normalize_order(:asc), do: "ASC"
  defp normalize_order(:desc), do: "DESC"
  defp normalize_order("asc"), do: "ASC"
  defp normalize_order("desc"), do: "DESC"
  defp normalize_order(_), do: "DESC"

  defp normalize_optional_string(value) when is_binary(value) and value != "", do: value
  defp normalize_optional_string(_), do: nil

  defp normalize_optional_integer(value) when is_integer(value), do: value
  defp normalize_optional_integer(_), do: nil

  defp maybe_put_prefix(opts, prefix) when is_binary(prefix) and prefix != "" do
    Keyword.put(opts, :prefix, prefix)
  end

  defp maybe_put_prefix(opts, _prefix), do: opts
end
