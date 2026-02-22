defmodule JidoStudio.Observability.Workflows do
  @moduledoc false

  alias JidoStudio.Observability.Correlation
  alias JidoStudio.Observability.Filters
  alias JidoStudio.Persistence

  @namespace "workflow_runs"
  @default_limit 120
  @default_stalled_after_ms :timer.minutes(5)

  @spec list_runs(keyword()) :: [map()]
  def list_runs(opts \\ []) do
    filters = Keyword.get(opts, :filters, %{}) |> parse_filters()
    limit = Filters.normalize_limit(Keyword.get(opts, :limit, @default_limit), @default_limit)
    bounds = Filters.time_bounds(filters)
    stalled_after = stalled_after_ms()

    Persistence.list_docs(@namespace,
      order: :desc,
      sort_by: :last_event_at,
      limit: max(limit * 4, 200)
    )
    |> Enum.map(&decorate_run(&1, stalled_after))
    |> Enum.filter(&matches_filters?(&1, filters, bounds))
    |> Enum.sort_by(&run_sort_key/1, :desc)
    |> Enum.take(limit)
  end

  @spec get_run(String.t()) :: {:ok, map()} | :not_found | {:error, term()}
  def get_run(run_id) when is_binary(run_id) do
    Persistence.get_doc(@namespace, run_id)
  end

  def get_run(_), do: :not_found

  @spec run_timeline(String.t(), keyword()) :: [map()]
  def run_timeline(run_id, opts \\ [])

  def run_timeline(run_id, opts) when is_binary(run_id) do
    limit = Filters.normalize_limit(Keyword.get(opts, :limit, 300), 300)

    workflow_stream(run_id)
    |> Persistence.read_events(order: :asc, limit: max(limit, 200))
    |> Enum.map(&Correlation.normalize/1)
    |> Enum.sort_by(&(&1[:ts] || 0), :asc)
    |> Enum.take(limit)
  end

  def run_timeline(_, _), do: []

  @spec stalled_after_ms() :: pos_integer()
  def stalled_after_ms do
    Application.get_env(:jido_studio, :workflow_stalled_after_ms, @default_stalled_after_ms)
    |> normalize_stalled_after_ms()
  end

  defp parse_filters(filters) do
    defaults =
      Filters.default_filters(%{
        range: "24h",
        status: "all",
        workflow_id: nil,
        agent_id: nil,
        project_id: nil,
        user_id: nil,
        query: nil,
        stalled_only: false,
        error_only: false
      })

    Filters.parse(filters, defaults)
  end

  defp decorate_run(run, stalled_after) do
    run =
      run
      |> Map.put(:duration_ms, duration(run))
      |> Map.put(:status, normalize_status(run[:status]))

    Map.put(run, :stalled?, stale_running?(run, stalled_after))
  end

  defp matches_filters?(run, filters, bounds) do
    ts = run_sort_key(run)

    Filters.within_bounds?(ts, bounds) and
      status_match?(run, filters) and
      stalled_match?(run, filters[:stalled_only]) and
      Filters.match_string(run[:workflow_id], filters[:workflow_id]) and
      Filters.match_string(run[:agent_id], filters[:agent_id]) and
      Filters.match_string(run[:project_id], filters[:project_id]) and
      Filters.match_string(run[:user_id], filters[:user_id]) and
      Filters.match_string(run[:trace_id], filters[:trace_id]) and
      Filters.match_string(run[:incident_id], filters[:incident_id]) and
      query_match?(run, filters[:query])
  end

  defp status_match?(run, %{error_only: true}), do: normalize_status(run[:status]) == "error"

  defp status_match?(_run, %{status: "all"}), do: true

  defp status_match?(run, %{status: status}) do
    normalize_status(run[:status]) == normalize_status(status)
  end

  defp status_match?(_run, _), do: true

  defp stalled_match?(_run, false), do: true
  defp stalled_match?(run, true), do: run[:stalled?] == true
  defp stalled_match?(_run, _), do: true

  defp query_match?(_run, nil), do: true

  defp query_match?(run, query) do
    query_text = String.downcase(to_string(query || ""))

    [
      run[:workflow_id],
      run[:run_id],
      run[:status],
      run[:trace_id],
      run[:agent_id],
      run[:incident_id],
      run[:last_step],
      inspect(run[:step_counts] || %{}, limit: 40)
    ]
    |> Enum.map(&to_string(&1 || ""))
    |> Enum.join(" ")
    |> String.downcase()
    |> String.contains?(query_text)
  end

  defp stale_running?(run, stalled_after) do
    status = normalize_status(run[:status])
    last_event_at = run[:last_event_at] || run[:updated_at] || 0

    status == "running" and is_integer(last_event_at) and last_event_at > 0 and
      now_ms() - last_event_at > stalled_after
  end

  defp duration(run) when is_map(run) do
    started_at = run[:started_at]
    ended_at = run[:ended_at]

    cond do
      is_integer(run[:duration_ms]) and run[:duration_ms] >= 0 ->
        run[:duration_ms]

      is_integer(started_at) and is_integer(ended_at) ->
        max(ended_at - started_at, 0)

      true ->
        nil
    end
  end

  defp duration(_), do: nil

  defp run_sort_key(run) when is_map(run) do
    run[:last_event_at] || run[:updated_at] || run[:started_at] || 0
  end

  defp run_sort_key(_), do: 0

  defp normalize_status(value) when value in [:running, :ok, :error], do: Atom.to_string(value)

  defp normalize_status(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))

    cond do
      normalized in ["running", "ok", "error"] -> normalized
      normalized in ["completed", "success"] -> "ok"
      normalized in ["failed", "exception"] -> "error"
      true -> "running"
    end
  end

  defp normalize_status(_), do: "running"

  defp workflow_stream(run_id), do: "workflow_run:" <> run_id

  defp normalize_stalled_after_ms(value) when is_integer(value) and value > 0, do: value

  defp normalize_stalled_after_ms({:seconds, value}) when is_integer(value) and value > 0,
    do: value * 1_000

  defp normalize_stalled_after_ms({:minutes, value}) when is_integer(value) and value > 0,
    do: value * 60_000

  defp normalize_stalled_after_ms(_), do: @default_stalled_after_ms

  defp now_ms, do: System.system_time(:millisecond)
end
