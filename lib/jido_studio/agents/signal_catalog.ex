defmodule JidoStudio.Agents.SignalCatalog do
  @moduledoc false

  @type signal_row :: %{
          key: String.t(),
          signal_type: String.t(),
          source: atom(),
          origins: [atom()],
          priority: integer(),
          target: term(),
          target_key: String.t(),
          target_summary: String.t(),
          has_matcher?: boolean(),
          matcher: String.t() | nil,
          route_available?: boolean(),
          entrypoint?: boolean(),
          advanced?: boolean(),
          internal?: boolean(),
          last_seen_at: integer() | nil
        }

  @spec build(module() | nil, map() | pid() | nil, keyword()) ::
          %{signals: [signal_row()], warnings: [String.t()], runtime_available?: boolean()}
  def build(agent_module, instance \\ nil, opts \\ []) do
    event_index = build_event_index(Keyword.get(opts, :events, []))

    {runtime_routes, runtime_warnings} = runtime_routes(instance, event_index)

    static_routes =
      static_routes(agent_module, event_index)
      |> Enum.reject(&is_nil/1)

    merged =
      (runtime_routes ++ static_routes)
      |> Enum.reduce(%{}, fn row, acc ->
        Map.update(acc, row.key, row, fn existing ->
          merge_rows(existing, row)
        end)
      end)
      |> Map.values()
      |> Enum.map(&finalize_row/1)
      |> Enum.sort_by(&sort_key/1)

    %{
      signals: merged,
      warnings: Enum.uniq(runtime_warnings),
      runtime_available?: runtime_routes != []
    }
  end

  defp runtime_routes(instance, event_index) do
    case extract_pid(instance) do
      pid when is_pid(pid) ->
        with {:ok, state} <- Jido.AgentServer.state(pid),
             router when is_map(router) <- Map.get(state, :signal_router),
             {:ok, routes} <- Jido.Signal.Router.list(router) do
          rows =
            routes
            |> List.wrap()
            |> Enum.map(&runtime_route_to_row(&1, event_index))
            |> Enum.reject(&is_nil/1)

          {rows, []}
        else
          {:error, reason} ->
            {[], ["Failed to load runtime signal router: #{inspect(reason)}"]}

          _ ->
            {[], []}
        end

      _ ->
        {[], []}
    end
  rescue
    error ->
      {[], ["Failed to inspect runtime signal router: " <> Exception.message(error)]}
  end

  defp runtime_route_to_row(%{path: path, target: target} = route, event_index) do
    priority = normalize_priority(route[:priority])
    matcher = route[:match]
    base_row(path, target, :runtime_router, priority, matcher, true, event_index)
  end

  defp runtime_route_to_row(_route, _event_index), do: nil

  defp static_routes(agent_module, event_index) when is_atom(agent_module) do
    strategy_routes(agent_module, event_index) ++
      agent_routes(agent_module, event_index) ++
      plugin_routes(agent_module, event_index)
  end

  defp static_routes(_, _), do: []

  defp strategy_routes(agent_module, event_index) do
    strategy =
      if function_exported?(agent_module, :strategy, 0), do: agent_module.strategy(), else: nil

    if is_atom(strategy) and function_exported?(strategy, :signal_routes, 1) do
      ctx = %{agent_module: agent_module, strategy_opts: safe_strategy_opts(agent_module)}

      strategy.signal_routes(ctx)
      |> normalize_route_specs(:strategy, event_index)
    else
      []
    end
  rescue
    _ -> []
  end

  defp agent_routes(agent_module, event_index) do
    if function_exported?(agent_module, :signal_routes, 1) do
      agent_module.signal_routes(%{agent_module: agent_module})
      |> normalize_route_specs(:agent, event_index)
    else
      []
    end
  rescue
    _ -> []
  end

  defp plugin_routes(agent_module, event_index) do
    plugin_routes =
      if function_exported?(agent_module, :plugin_routes, 0) do
        agent_module.plugin_routes()
      else
        []
      end

    plugin_routes
    |> List.wrap()
    |> Enum.map(fn route ->
      source =
        case route do
          {path, _target, _priority} when is_binary(path) ->
            if String.contains?(path, ".__schedule__."), do: :plugin_schedule, else: :plugin

          {path, _target, opts} when is_binary(path) and is_list(opts) ->
            if String.contains?(path, ".__schedule__."), do: :plugin_schedule, else: :plugin

          _ ->
            :plugin
        end

      normalize_route_spec(route, source, event_index)
    end)
    |> Enum.reject(&is_nil/1)
  rescue
    _ -> []
  end

  defp normalize_route_specs(route_specs, source, event_index) do
    route_specs
    |> List.wrap()
    |> Enum.map(&normalize_route_spec(&1, source, event_index))
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_route_spec({path, target}, source, event_index) when is_binary(path) do
    base_row(path, target, source, 0, nil, false, event_index)
  end

  defp normalize_route_spec({path, target, priority}, source, event_index)
       when is_binary(path) and is_integer(priority) do
    base_row(path, target, source, normalize_priority(priority), nil, false, event_index)
  end

  defp normalize_route_spec({path, target, opts}, source, event_index)
       when is_binary(path) and is_list(opts) do
    priority = normalize_priority(Keyword.get(opts, :priority, 0))
    base_row(path, target, source, priority, nil, false, event_index)
  end

  defp normalize_route_spec({path, match_fn, target}, source, event_index)
       when is_binary(path) and is_function(match_fn, 1) do
    base_row(path, target, source, 0, match_fn, false, event_index)
  end

  defp normalize_route_spec({path, match_fn, target, priority}, source, event_index)
       when is_binary(path) and is_function(match_fn, 1) and is_integer(priority) do
    base_row(path, target, source, normalize_priority(priority), match_fn, false, event_index)
  end

  defp normalize_route_spec(_route_spec, _source, _event_index), do: nil

  defp base_row(signal_type, target, source, priority, matcher, runtime_available?, event_index) do
    signal_type = normalize_signal_type(signal_type)
    target_key = target_key(target)
    key = signal_type <> "::" <> target_key
    advanced? = advanced_signal?(signal_type, source, target)
    internal? = internal_signal?(signal_type, source, target)

    %{
      key: key,
      signal_type: signal_type,
      source: source,
      origins: [source],
      priority: normalize_priority(priority),
      target: target,
      target_key: target_key,
      target_summary: target_summary(target),
      has_matcher?: is_function(matcher, 1),
      matcher: if(is_function(matcher, 1), do: short_matcher(matcher), else: nil),
      route_available?: runtime_available?,
      entrypoint?: not advanced?,
      advanced?: advanced?,
      internal?: internal?,
      last_seen_at: Map.get(event_index, signal_type)
    }
  end

  defp merge_rows(%{} = existing, %{} = incoming) do
    runtime_preferred = incoming.source == :runtime_router
    preferred = if(runtime_preferred, do: incoming, else: existing)

    preferred
    |> Map.put(
      :origins,
      (List.wrap(existing.origins) ++ List.wrap(incoming.origins)) |> Enum.uniq()
    )
    |> Map.put(:route_available?, existing.route_available? || incoming.route_available?)
    |> Map.put(:last_seen_at, max_timestamp(existing.last_seen_at, incoming.last_seen_at))
    |> Map.put(:advanced?, existing.advanced? || incoming.advanced?)
    |> Map.put(:internal?, existing.internal? || incoming.internal?)
    |> Map.put(:entrypoint?, not (existing.advanced? || incoming.advanced?))
  end

  defp finalize_row(%{} = row) do
    row
    |> Map.update(:origins, [], &Enum.uniq(List.wrap(&1)))
    |> Map.put(:entrypoint?, row.advanced? != true)
    |> Map.put(:dispatch_ref, %{kind: :signal, signal_type: row.signal_type, source: row.source})
  end

  defp sort_key(%{} = row) do
    {
      if(row.entrypoint?, do: 0, else: 1),
      if(row.route_available?, do: 0, else: 1),
      String.downcase(to_string(row.signal_type || "")),
      -normalize_priority(row.priority)
    }
  end

  defp build_event_index(events) when is_list(events) do
    Enum.reduce(events, %{}, fn event, acc ->
      metadata = Map.get(event, :metadata, %{})

      signal_type =
        metadata[:signal_type] || metadata["signal_type"] || metadata[:type] || metadata["type"]

      timestamp = normalize_timestamp(event[:timestamp_ms] || event["timestamp_ms"])

      if is_binary(signal_type) and is_integer(timestamp) do
        Map.update(acc, signal_type, timestamp, &max(&1, timestamp))
      else
        acc
      end
    end)
  end

  defp build_event_index(_), do: %{}

  defp advanced_signal?(signal_type, source, target) do
    String.starts_with?(signal_type, "jido.") or
      String.contains?(signal_type, ".__schedule__.") or
      String.contains?(signal_type, ".llm.") or
      String.contains?(signal_type, ".trace.") or
      source in [:plugin_schedule] or
      noop_target?(target)
  end

  defp internal_signal?(signal_type, source, target) do
    advanced_signal?(signal_type, source, target) or String.contains?(signal_type, ".internal.")
  end

  defp noop_target?(module) when is_atom(module), do: module == Jido.Actions.Control.Noop

  defp noop_target?({module, _}) when is_atom(module),
    do: module == Jido.Actions.Control.Noop

  defp noop_target?(_), do: false

  defp short_matcher(function), do: inspect(function, limit: 10, printable_limit: 400)

  defp target_summary(target) when is_atom(target), do: inspect(target)

  defp target_summary({:strategy_cmd, action}), do: "strategy_cmd:" <> inspect(action)
  defp target_summary({:custom, value}), do: "custom:" <> inspect(value, limit: 20)
  defp target_summary({module, _opts}) when is_atom(module), do: inspect(module)

  defp target_summary(list) when is_list(list) do
    "multi(" <> Integer.to_string(length(list)) <> ")"
  end

  defp target_summary(other), do: inspect(other, limit: 20, printable_limit: 800)

  defp target_key({:strategy_cmd, action}), do: "strategy:" <> inspect(action)
  defp target_key({:custom, action}), do: "custom:" <> inspect(action)
  defp target_key(target) when is_atom(target), do: "module:" <> inspect(target)
  defp target_key({module, _opts}) when is_atom(module), do: "module:" <> inspect(module)

  defp target_key(list) when is_list(list) do
    "multi:" <> Integer.to_string(:erlang.phash2(list))
  end

  defp target_key(other), do: "target:" <> Integer.to_string(:erlang.phash2(other))

  defp extract_pid(%{pid: pid}) when is_pid(pid), do: pid
  defp extract_pid(%{active_instance_pid: pid}) when is_pid(pid), do: pid
  defp extract_pid(pid) when is_pid(pid), do: pid
  defp extract_pid(_), do: nil

  defp safe_strategy_opts(agent_module) when is_atom(agent_module) do
    if function_exported?(agent_module, :strategy_opts, 0),
      do: agent_module.strategy_opts(),
      else: []
  rescue
    _ -> []
  end

  defp safe_strategy_opts(_), do: []

  defp normalize_signal_type(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "unknown.signal"
      normalized -> normalized
    end
  end

  defp normalize_signal_type(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_signal_type(_), do: "unknown.signal"

  defp normalize_priority(value) when is_integer(value), do: value
  defp normalize_priority(_), do: 0

  defp normalize_timestamp(value) when is_integer(value), do: value
  defp normalize_timestamp(_), do: nil

  defp max_timestamp(nil, value), do: value
  defp max_timestamp(value, nil), do: value
  defp max_timestamp(left, right), do: max(left, right)
end
