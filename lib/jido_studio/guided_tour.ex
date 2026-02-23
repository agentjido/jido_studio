defmodule JidoStudio.GuidedTour do
  @moduledoc false

  alias JidoStudio.ProductMetrics

  @flows [
    %{
      key: "first_5_minutes",
      label: "First 5 Minutes",
      description:
        "Get oriented quickly: health, attention items, fleet state, diagnostics path, and setup status.",
      duration_minutes: 5,
      steps: [
        %{
          key: "home_health_summary",
          title: "Start With Fleet Health",
          body:
            "Read the Home summary first to confirm the selected runtime and node are healthy.",
          path: "/",
          selector: ~s([data-tour-id="home-health-summary"]),
          fallback:
            "If Home health is unavailable, refresh Home and keep runtime/node scope selected."
        },
        %{
          key: "home_attention_list",
          title: "Check Attention Needed",
          body:
            "Use Attention Needed to find the fastest path from symptom to action before deep debugging.",
          path: "/",
          selector: ~s([data-tour-id="home-attention-list"]),
          fallback:
            "If no attention items are shown, continue to Agents to inspect active instances."
        },
        %{
          key: "agents_active_instances",
          title: "Open Active Instances",
          body:
            "Review active instances and follow one to inspect runtime state and interaction readiness.",
          path: "/agents",
          selector: ~s([data-tour-id="agents-active-instances"]),
          fallback:
            "If there are no instances yet, keep this view open and start one from your host runtime."
        },
        %{
          key: "diagnostics_timeline_toggle",
          title: "Use Timeline For Root Cause",
          body:
            "Switch Diagnostics into Timeline mode when you need span-level context and deep links.",
          path: "/diagnostics?view=timeline",
          selector: ~s([data-tour-id="diagnostics-timeline-toggle"]),
          fallback:
            "If Timeline toggle is unavailable, open Diagnostics and verify view controls are visible."
        },
        %{
          key: "settings_setup_reentry",
          title: "Confirm Setup Re-entry",
          body:
            "Use Settings as your setup control point to re-test runtime checks and profile guidance.",
          path: "/settings",
          selector: ~s([data-tour-id="settings-setup-assistant"]),
          fallback:
            "If setup status is unavailable, verify runtime selection and reopen Settings from the sidebar."
        }
      ]
    },
    %{
      key: "setup_and_first_interaction",
      label: "Setup + First Interaction",
      description:
        "Walk through setup checks and the first safe interaction path for new operators.",
      duration_minutes: 6,
      steps: [
        %{
          key: "home_setup_assistant",
          title: "Validate Setup On Home",
          body:
            "Use Setup Assistant on Home to quickly confirm runtime connectivity, persistence, and smoke readiness.",
          path: "/",
          selector: ~s([data-tour-id="home-setup-assistant"]),
          fallback:
            "If setup guidance is hidden, click Show Setup and continue with the checklist."
        },
        %{
          key: "settings_setup_assistant",
          title: "Re-test Setup In Settings",
          body:
            "Open Settings to re-test setup health and inspect profile guidance in a dedicated configuration surface.",
          path: "/settings",
          selector: ~s([data-tour-id="settings-setup-assistant"]),
          fallback: "If setup card is unavailable, refresh Settings and check runtime scope."
        },
        %{
          key: "agents_live_ops_scope",
          title: "Set Live Ops Scope",
          body:
            "Before interacting, set project/user/agent scope so the instance list reflects the exact target context.",
          path: "/agents",
          selector: ~s([data-tour-id="agents-live-ops-scope"]),
          fallback:
            "If scope controls are unavailable, reopen Agents and ensure Live Ops is enabled."
        },
        %{
          key: "agents_instances_for_interaction",
          title: "Pick An Active Instance",
          body: "Use Active Instances to choose where to run your first guarded interaction.",
          path: "/agents",
          selector: ~s([data-tour-id="agents-active-instances"]),
          fallback:
            "If no instances exist yet, start an instance from your host app and return to this step."
        },
        %{
          key: "agents_inventory_explainer",
          title: "Understand Discovered vs Running",
          body:
            "Use the inventory explainer so discovered module counts and running instance counts are unambiguous.",
          path: "/agents",
          selector: ~s([data-tour-id="agents-inventory-explainer"]),
          fallback:
            "If this explainer is unavailable, continue with Active Instances and keep runtime/node scope fixed."
        },
        %{
          key: "agents_starter_agent",
          title: "Launch The Starter Module",
          body:
            "Open the Starter Agent card to land on the module with start modal pre-opened (`start=1`).",
          path: "/agents",
          selector: ~s([data-tour-id="agents-starter-agent"]),
          fallback:
            "If no starter is available, open Product Agents and choose the first deterministic agent module."
        }
      ]
    },
    %{
      key: "incident_triage",
      label: "Incident Triage",
      description: "Follow the warning-to-root-cause path used in on-call workflows.",
      duration_minutes: 4,
      steps: [
        %{
          key: "triage_from_attention",
          title: "Start From Attention",
          body: "When incidents happen, begin on Home and open the most relevant attention item.",
          path: "/",
          selector: ~s([data-tour-id="home-attention-list"]),
          fallback:
            "If no incident cards are present, continue with Diagnostics to practice the triage flow."
        },
        %{
          key: "diagnostics_timeline_mode",
          title: "Open Timeline Mode",
          body:
            "Timeline mode is the fastest path from warning context to concrete span-level root cause.",
          path: "/diagnostics?view=timeline",
          selector: ~s([data-tour-id="diagnostics-timeline-toggle"]),
          fallback:
            "If Timeline cannot be selected, verify node scope and switch from All Nodes to a concrete node."
        },
        %{
          key: "diagnostics_trace_picker",
          title: "Choose Trace Scope",
          body:
            "Select a trace before filtering lanes or critical path so you inspect one incident at a time.",
          path: "/diagnostics?view=timeline",
          selector: ~s([data-tour-id="diagnostics-trace-picker"]),
          fallback:
            "If no traces are available, keep the workflow and retry after runtime activity is generated."
        },
        %{
          key: "diagnostics_waterfall_root_cause",
          title: "Inspect Waterfall And Span Details",
          body:
            "Use the waterfall and span details to move from symptom to actionable root-cause next steps.",
          path: "/diagnostics?view=timeline",
          selector: ~s([data-tour-id="diagnostics-timeline-waterfall"]),
          fallback:
            "If waterfall data is sparse, continue with deep links from span details once a trace is selected."
        }
      ]
    }
  ]

  @spec flows() :: [map()]
  def flows, do: @flows

  @spec flow(String.t() | nil) :: map() | nil
  def flow(key) when is_binary(key) do
    Enum.find(@flows, &(&1.key == String.trim(key)))
  end

  def flow(_), do: nil

  @spec flows_json() :: String.t()
  def flows_json do
    Jason.encode!(@flows)
  end

  @spec track_metric(map(), map()) :: map()
  def track_metric(socket, params) when is_map(socket) and is_map(params) do
    kind = normalize_optional_string(params["kind"])

    opts =
      []
      |> Keyword.put(:source, "guided_tour")
      |> maybe_put_keyword(:flow, normalize_optional_string(params["flow"]))
      |> maybe_put_keyword(:step_key, normalize_optional_string(params["step_key"]))
      |> maybe_put_keyword(:step_index, parse_optional_integer(params["step_index"]))
      |> maybe_put_keyword(:total_steps, parse_optional_integer(params["total_steps"]))
      |> maybe_put_keyword(:mode, normalize_optional_string(params["mode"]))
      |> maybe_put_keyword(:status, normalize_optional_string(params["status"]))

    case kind do
      "started" ->
        :ok = ProductMetrics.tour_started(socket, opts)

      "step_viewed" ->
        :ok = ProductMetrics.tour_step_viewed(socket, opts)

      "step_completed" ->
        :ok = ProductMetrics.tour_step_completed(socket, opts)

      "dismissed" ->
        :ok = ProductMetrics.tour_dismissed(socket, opts)

      "completed" ->
        :ok = ProductMetrics.tour_completed(socket, opts)

      _ ->
        :ok
    end

    socket
  end

  defp maybe_put_keyword(opts, _key, nil), do: opts
  defp maybe_put_keyword(opts, key, value), do: Keyword.put(opts, key, value)

  defp parse_optional_integer(value) when is_integer(value), do: value

  defp parse_optional_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, _rest} -> parsed
      _ -> nil
    end
  end

  defp parse_optional_integer(_), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil
end
