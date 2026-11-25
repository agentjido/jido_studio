defmodule JidoStudio.Agents.InstanceIndex do
  @moduledoc false

  alias JidoStudio.LiveOps

  @type row :: %{
          instance_id: String.t(),
          pid: pid() | nil,
          agent_slug: String.t() | nil,
          agent_name: String.t() | nil,
          agent_module: module() | nil,
          agent_tags: [String.t()],
          status: String.t(),
          started_at: DateTime.t() | nil,
          last_activity_at: DateTime.t() | nil,
          uptime_ms: non_neg_integer() | nil,
          viewer_count: non_neg_integer(),
          project_id: String.t() | nil,
          user_id: String.t() | nil
        }

  @spec build_rows([map()], keyword()) :: [row()]
  def build_rows(agents, opts \\ [])

  def build_rows(agents, opts) when is_list(agents) do
    viewer_count_fun = Keyword.get(opts, :viewer_count_fun, &LiveOps.viewer_count/1)
    trace_events = Keyword.get(opts, :trace_events, [])
    now = Keyword.get(opts, :now, DateTime.utc_now())

    event_index = build_event_index(trace_events)

    agents
    |> Enum.flat_map(fn agent ->
      instances = Map.get(agent, :running_instances, [])

      Enum.map(instances, fn instance ->
        instance_id = normalize_id(instance[:id])
        pid = instance[:pid]
        runtime_status = runtime_status(pid)
        details = snapshot_details(runtime_status)
        event_meta = Map.get(event_index, instance_id, %{})

        started_at =
          first_present_datetime([
            details[:started_at],
            details["started_at"],
            details[:booted_at],
            details["booted_at"],
            event_meta[:first_ts]
          ])

        last_activity_at =
          first_present_datetime([
            details[:last_activity_at],
            details["last_activity_at"],
            details[:updated_at],
            details["updated_at"],
            event_meta[:last_ts]
          ])

        scope = event_meta[:scope] || %{}

        %{
          instance_id: instance_id,
          pid: pid,
          agent_slug: agent[:slug],
          agent_name: agent[:name],
          agent_module: agent[:module],
          agent_tags: normalize_tags(agent[:tags]),
          status: status_string(runtime_status),
          started_at: started_at,
          last_activity_at: last_activity_at,
          uptime_ms: uptime_ms(started_at, now),
          viewer_count: safe_viewer_count(viewer_count_fun, instance_id),
          project_id: normalize_optional_string(scope[:project_id] || scope["project_id"]),
          user_id: normalize_optional_string(scope[:user_id] || scope["user_id"])
        }
      end)
    end)
  end

  def build_rows(_, _), do: []

  defp runtime_status(pid) when is_pid(pid) do
    case Jido.AgentServer.status(pid) do
      {:ok, status} -> status
      _ -> nil
    end
  rescue
    _ -> nil
  end

  defp runtime_status(_), do: nil

  defp snapshot_details(%{snapshot: %{details: details}}) when is_map(details), do: details
  defp snapshot_details(_), do: %{}

  defp status_string(%{snapshot: %{status: status}}) when not is_nil(status) do
    status
    |> to_string()
    |> String.downcase()
  end

  defp status_string(_), do: "offline"

  defp build_event_index(events) when is_list(events) do
    Enum.reduce(events, %{}, fn event, acc ->
      instance_id = normalize_optional_string(event[:instance_id] || event[:agent_id])
      ts = timestamp_ms(event[:timestamp_ms])

      if is_binary(instance_id) and is_integer(ts) do
        existing = Map.get(acc, instance_id, %{first_ts: ts, last_ts: ts, scope: %{}})

        updated = %{
          first_ts: min(existing[:first_ts] || ts, ts),
          last_ts: max(existing[:last_ts] || ts, ts),
          scope: merge_scope(existing[:scope], event[:scope] || event[:metadata] || %{})
        }

        Map.put(acc, instance_id, updated)
      else
        acc
      end
    end)
  end

  defp build_event_index(_), do: %{}

  defp merge_scope(existing, incoming) when is_map(existing) and is_map(incoming) do
    scoped = incoming[:scope] || incoming["scope"] || incoming

    if is_map(scoped) do
      Map.merge(existing, scoped)
    else
      existing
    end
  end

  defp merge_scope(existing, _), do: existing

  defp first_present_datetime([head | tail]) do
    case to_datetime(head) do
      nil -> first_present_datetime(tail)
      value -> value
    end
  end

  defp first_present_datetime([]), do: nil

  defp to_datetime(%DateTime{} = dt), do: dt

  defp to_datetime(value) when is_integer(value) do
    case DateTime.from_unix(value, :millisecond) do
      {:ok, dt} -> dt
      _ -> nil
    end
  end

  defp to_datetime(value) when is_binary(value) do
    value
    |> String.trim()
    |> case do
      "" ->
        nil

      trimmed ->
        case DateTime.from_iso8601(trimmed) do
          {:ok, dt, _} -> dt
          _ -> nil
        end
    end
  end

  defp to_datetime(_), do: nil

  defp uptime_ms(nil, _now), do: nil

  defp uptime_ms(%DateTime{} = started_at, %DateTime{} = now) do
    max(DateTime.diff(now, started_at, :millisecond), 0)
  end

  defp uptime_ms(_, _), do: nil

  defp safe_viewer_count(fun, instance_id) when is_function(fun, 1) and is_binary(instance_id) do
    case fun.(instance_id) do
      value when is_integer(value) and value >= 0 -> value
      _ -> 0
    end
  rescue
    _ -> 0
  end

  defp safe_viewer_count(_, _), do: 0

  defp normalize_id(value) do
    normalize_optional_string(value) || "unknown"
  end

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_), do: nil

  defp normalize_tags(tags) when is_list(tags) do
    tags
    |> Enum.map(&normalize_optional_string/1)
    |> Enum.reject(&is_nil/1)
  end

  defp normalize_tags(_), do: []

  defp timestamp_ms(value) when is_integer(value), do: value
  defp timestamp_ms(_), do: nil
end
