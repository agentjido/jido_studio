defmodule JidoStudio.Live.HomeLive.State do
  @moduledoc false

  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Onboarding.StarterAgent
  alias JidoStudio.ScopeQuery
  alias JidoStudio.Setup
  alias JidoStudio.Setup.Helpers
  alias JidoStudio.Setup.Profiles

  @typep options :: [
           scope: term(),
           prefix: String.t(),
           runtime_key: String.t() | nil,
           node_param: String.t() | nil,
           agents: [map()],
           incidents: [map()],
           traces: [map()],
           storage_info: %{adapter: String.t(), path: String.t()},
           thread_persistence?: boolean(),
           setup_assistant: map(),
           selected_setup_profile: String.t() | nil
         ]

  @spec build(options()) :: map()
  def build(opts) when is_list(opts) do
    scope = Keyword.fetch!(opts, :scope)
    prefix = Keyword.fetch!(opts, :prefix)
    runtime_key = Keyword.get(opts, :runtime_key)
    node_param = Keyword.get(opts, :node_param, "all")
    agents = List.wrap(Keyword.get(opts, :agents, []))
    incidents = List.wrap(Keyword.get(opts, :incidents, []))
    traces = List.wrap(Keyword.get(opts, :traces, []))
    storage_info = Keyword.get(opts, :storage_info, %{adapter: "n/a", path: "n/a"})
    thread_persistence? = Keyword.get(opts, :thread_persistence?, false)
    setup_assistant = Keyword.get(opts, :setup_assistant, %{checks: []})
    selected_setup_profile = Keyword.get(opts, :selected_setup_profile)

    summary = summary(scope, agents, incidents, storage_info, thread_persistence?)
    top_agents = top_agents(agents)

    product_agents = StarterAgent.product_agents(agents)
    {starter_agent, starter_reason} = StarterAgent.pick(product_agents)

    attention_items =
      attention_items(summary, traces,
        prefix: prefix,
        runtime_key: runtime_key,
        node_param: node_param
      )

    setup = setup_state(setup_assistant, selected_setup_profile)

    %{
      summary: summary,
      top_agents: top_agents,
      attention_items: attention_items,
      recent_activity: recent_activity(traces),
      recent_failures: recent_failures(incidents),
      starter_agent: starter_agent,
      starter_reason: starter_reason,
      starter_running?: starter_running?(starter_agent),
      setup_assistant: setup.assistant,
      setup_profile: setup.profile,
      setup_statuses: setup.statuses,
      next_step_metrics: %{
        linked_count: Enum.count(attention_items, &is_binary(&1[:path])),
        total_count: length(attention_items)
      }
    }
  end

  @spec summary(term(), [map()], [map()], map(), boolean()) :: map()
  def summary(scope, agents, incidents, storage_info, thread_persistence?) do
    %{
      online_agents: Enum.count(agents, &((&1.running_instances || []) != [])),
      available_agents: Enum.count(agents, &((&1.running_instances || []) == [])),
      running_instances: Enum.reduce(agents, 0, &(&2 + length(&1.running_instances || []))),
      active_incidents: Enum.count(incidents, &incident_active?/1),
      node_count: node_count(scope),
      thread_persistence?: thread_persistence?,
      thread_storage_adapter: storage_info[:adapter],
      thread_storage_path: storage_info[:path]
    }
  end

  @spec top_agents([map()]) :: [map()]
  def top_agents(agents) do
    agents
    |> Enum.sort_by(&length(&1.running_instances || []), :desc)
    |> Enum.take(5)
  end

  @spec attention_items(map(), [map()], keyword()) :: [map()]
  def attention_items(summary, traces, opts) do
    prefix = Keyword.get(opts, :prefix, "")
    runtime_key = Keyword.get(opts, :runtime_key)
    node_param = Keyword.get(opts, :node_param, "all")

    []
    |> maybe_add_attention(summary.active_incidents > 0, %{
      kind: "active_incidents",
      title: "#{summary.active_incidents} active incidents",
      description: "Open Activity or Diagnostics to inspect current failures and timelines.",
      path: page_path(prefix, "/activity", runtime_key, node_param)
    })
    |> maybe_add_attention(Enum.any?(traces, &(&1[:status] == "error")), %{
      kind: "recent_error_trace",
      title: "Recent error traces detected",
      description: "A trace ended with errors in the current scope within the recent window.",
      path: page_path(prefix, "/diagnostics", runtime_key, node_param)
    })
  end

  @spec recent_activity([map()]) :: [map()]
  def recent_activity(traces) do
    traces
    |> Enum.take(8)
    |> Enum.map(fn trace ->
      %{
        title: trace[:trace_id] || trace[:id] || "trace",
        subtitle:
          [trace[:agent_id], trace[:status]] |> Enum.reject(&is_nil/1) |> Enum.join(" / "),
        when: format_timestamp(trace[:last_event_at] || trace[:started_at])
      }
    end)
  end

  @spec recent_failures([map()]) :: [map()]
  def recent_failures(incidents) do
    incidents
    |> Enum.filter(&incident_active?/1)
    |> Enum.take(5)
    |> Enum.map(fn incident ->
      %{
        title: failure_title(incident),
        subtitle: failure_subtitle(incident),
        when: format_timestamp(incident[:last_event_at] || incident[:started_at])
      }
    end)
  end

  @spec setup_state(map(), String.t() | nil) :: %{
          assistant: map(),
          profile: map(),
          statuses: map()
        }
  def setup_state(setup_assistant, selected_setup_profile) do
    selected_profile_key =
      Helpers.normalize_profile_key(selected_setup_profile, setup_assistant.active_profile_key)

    assistant = Map.put(setup_assistant, :active_profile_key, selected_profile_key)

    %{
      assistant: assistant,
      profile: Profiles.find_profile(selected_profile_key),
      statuses: Setup.check_statuses(assistant)
    }
  end

  @spec starter_running?(map() | nil) :: boolean()
  def starter_running?(%{running_instances: instances}) when is_list(instances),
    do: instances != []

  def starter_running?(_), do: false

  defp incident_active?(incident) when is_map(incident) do
    status = to_string(incident[:status] || "")
    error_count = incident[:error_count] || 0

    status == "error" or error_count > 0
  end

  defp incident_active?(_), do: false

  defp node_count(:all), do: length(Scope.available_nodes())
  defp node_count(_), do: 1

  defp maybe_add_attention(items, true, item), do: [item | items]
  defp maybe_add_attention(items, false, _item), do: items

  defp failure_title(incident) when is_map(incident) do
    incident[:latest_action] || incident[:latest_signal_type] || incident[:incident_id] ||
      "incident"
  end

  defp failure_title(_incident), do: "incident"

  defp failure_subtitle(incident) when is_map(incident) do
    [incident[:latest_agent_id], incident[:status]]
    |> Enum.reject(&is_nil/1)
    |> Enum.map(&to_string/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.join(" / ")
    |> case do
      "" -> "failure"
      value -> value
    end
  end

  defp failure_subtitle(_incident), do: "failure"

  defp format_timestamp(ts) when is_integer(ts) and ts > 0 do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp format_timestamp(_), do: "-"

  defp page_path(prefix, suffix, runtime_key, node_param) do
    ScopeQuery.with_scope_query(prefix <> suffix, runtime_key, node_param)
  end
end
