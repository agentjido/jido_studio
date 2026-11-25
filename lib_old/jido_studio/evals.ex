defmodule JidoStudio.Evals do
  @moduledoc false

  alias JidoStudio.Persistence
  alias JidoStudio.Tracing

  @eval_runs_namespace "eval_runs"

  @default_max_duration_ms 20_000
  @default_tool_failure_ratio 0.25
  @default_required_span_substrings ["agent.cmd"]

  @spec enabled?() :: boolean()
  def enabled? do
    :jido_studio
    |> Application.get_env(:evals, [])
    |> Keyword.get(:enabled, true) == true
  end

  @spec default_rule_set() :: [map()]
  def default_rule_set do
    [
      %{id: :no_exceptions, weight: 0.35},
      %{id: :max_duration, weight: 0.25, threshold_ms: @default_max_duration_ms},
      %{id: :tool_failure_ratio, weight: 0.20, threshold: @default_tool_failure_ratio},
      %{id: :required_span_presence, weight: 0.20, required: @default_required_span_substrings}
    ]
  end

  @spec run_trace(String.t(), atom() | [map()], keyword()) :: {:ok, map()} | {:error, term()}
  def run_trace(trace_id, rule_set \\ :default, opts \\ [])

  def run_trace(trace_id, rule_set, opts) when is_binary(trace_id) do
    with true <- enabled?() or {:error, :disabled},
         {:ok, trace} <- Tracing.get_trace(trace_id) do
      spans = Tracing.list_trace_spans(trace_id, limit: Keyword.get(opts, :span_limit, 5_000))

      events =
        Tracing.list_trace_events(trace_id,
          order: :asc,
          limit: Keyword.get(opts, :event_limit, 4_000)
        )

      rules = resolve_rule_set(rule_set)

      evaluations = Enum.map(rules, &evaluate_rule(&1, trace, spans, events))
      weighted_score = score(evaluations)
      status = if(weighted_score >= 70, do: :pass, else: :fail)
      run_id = next_run_id(trace_id)

      run = %{
        id: "#{trace_id}:#{run_id}",
        run_id: run_id,
        trace_id: trace_id,
        rule_set: rule_set_name(rule_set),
        status: status,
        score: weighted_score,
        evaluations: evaluations,
        inserted_at: now_ms()
      }

      :ok = Persistence.put_doc(@eval_runs_namespace, run.id, run)

      {:ok, run}
    else
      :not_found -> {:error, :trace_not_found}
      {:error, _} = error -> error
      false -> {:error, :disabled}
    end
  end

  def run_trace(_, _, _), do: {:error, :invalid_trace_id}

  @spec list_runs(String.t(), keyword()) :: [map()]
  def list_runs(trace_id, opts \\ [])

  def list_runs(trace_id, opts) when is_binary(trace_id) do
    limit = normalize_limit(Keyword.get(opts, :limit, 20), 20)

    Persistence.list_docs(@eval_runs_namespace,
      order: :desc,
      limit: limit * 4,
      sort_by: :inserted_at
    )
    |> Enum.filter(&(&1[:trace_id] == trace_id))
    |> Enum.sort_by(&Map.get(&1, :inserted_at, 0), :desc)
    |> Enum.take(limit)
  end

  def list_runs(_, _), do: []

  @spec evals_enabled_for_ui?() :: boolean()
  def evals_enabled_for_ui? do
    enabled?() and :default in configured_rule_sets()
  end

  defp resolve_rule_set(:default), do: default_rule_set()

  defp resolve_rule_set(name) when is_atom(name) do
    if name in configured_rule_sets(), do: default_rule_set(), else: default_rule_set()
  end

  defp resolve_rule_set(rules) when is_list(rules), do: rules
  defp resolve_rule_set(_), do: default_rule_set()

  defp configured_rule_sets do
    :jido_studio
    |> Application.get_env(:evals, [])
    |> Keyword.get(:rule_sets, [:default])
    |> List.wrap()
  end

  defp rule_set_name(name) when is_atom(name), do: name
  defp rule_set_name(_), do: :custom

  defp evaluate_rule(%{id: :no_exceptions} = rule, trace, spans, events) do
    event_error? =
      Enum.any?(events, fn event ->
        type = event[:type] || event["type"]
        type in [:exception, "exception"]
      end)

    span_error? = Enum.any?(spans, &(&1[:error] == true or &1["error"] == true))
    passed = trace[:error] != true and not span_error? and not event_error?

    %{
      id: :no_exceptions,
      passed: passed,
      weight: weight(rule),
      detail:
        if(
          passed,
          do: "No exception markers in trace/spans/events.",
          else: "Exceptions were observed."
        )
    }
  end

  defp evaluate_rule(%{id: :max_duration} = rule, trace, _spans, _events) do
    threshold = normalize_limit(rule[:threshold_ms], @default_max_duration_ms)
    duration = trace[:duration_ms] || 0
    passed = is_integer(duration) and duration <= threshold

    %{
      id: :max_duration,
      passed: passed,
      weight: weight(rule),
      detail: "duration=#{duration}ms threshold=#{threshold}ms"
    }
  end

  defp evaluate_rule(%{id: :tool_failure_ratio} = rule, _trace, _spans, events) do
    threshold = normalize_ratio(rule[:threshold], @default_tool_failure_ratio)

    {tool_total, tool_errors} =
      Enum.reduce(events, {0, 0}, fn event, {total, errors} ->
        type = event[:entity_type] || event["entity_type"]
        status = event[:status] || event["status"]
        prefix = event[:event_prefix] || event["event_prefix"] || []

        is_tool? = type in [:tool, "tool"] or Enum.member?(prefix, :tool)

        is_error? =
          status in [:error, "error"] or
            (event[:type] || event["type"]) in [:exception, "exception"]

        if is_tool? do
          {total + 1, errors + if(is_error?, do: 1, else: 0)}
        else
          {total, errors}
        end
      end)

    ratio =
      case tool_total do
        0 -> 0.0
        _ -> tool_errors / tool_total
      end

    passed = ratio <= threshold

    %{
      id: :tool_failure_ratio,
      passed: passed,
      weight: weight(rule),
      detail: "tool_errors=#{tool_errors} tool_total=#{tool_total} ratio=#{Float.round(ratio, 4)}"
    }
  end

  defp evaluate_rule(%{id: :required_span_presence} = rule, _trace, spans, _events) do
    required = List.wrap(rule[:required] || @default_required_span_substrings)

    span_names =
      spans
      |> Enum.map(fn span -> to_string(span[:event_name] || "") end)
      |> Enum.join(" ")
      |> String.downcase()

    missing =
      Enum.filter(required, fn token ->
        not String.contains?(span_names, String.downcase(to_string(token)))
      end)

    passed = missing == []

    %{
      id: :required_span_presence,
      passed: passed,
      weight: weight(rule),
      detail:
        if(passed,
          do: "All required span markers present.",
          else: "Missing markers: #{Enum.join(missing, ", ")}"
        )
    }
  end

  defp evaluate_rule(rule, _trace, _spans, _events) do
    %{
      id: Map.get(rule, :id, :unknown),
      passed: true,
      weight: weight(rule),
      detail: "Unknown rule skipped."
    }
  end

  defp score(evaluations) do
    total_weight =
      evaluations
      |> Enum.map(&(&1[:weight] || 0.0))
      |> Enum.sum()
      |> max(0.0001)

    passed_weight =
      evaluations
      |> Enum.filter(&(&1[:passed] == true))
      |> Enum.map(&(&1[:weight] || 0.0))
      |> Enum.sum()

    round(passed_weight / total_weight * 100)
  end

  defp next_run_id(trace_id) do
    seq =
      list_runs(trace_id, limit: 1)
      |> List.first()
      |> case do
        nil -> 1
        run -> (run[:run_id] || 0) + 1
      end

    to_string(seq)
  end

  defp weight(rule) do
    value = rule[:weight] || 0.0
    if is_number(value) and value > 0, do: value * 1.0, else: 0.1
  end

  defp normalize_ratio(value, _default) when is_number(value) and value >= 0 and value <= 1,
    do: value * 1.0

  defp normalize_ratio(_value, default), do: default

  defp normalize_limit(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_limit(_value, default), do: default

  defp now_ms, do: System.system_time(:millisecond)
end
