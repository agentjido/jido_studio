defmodule JidoStudio.GuideLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.AgentRegistry
  alias JidoStudio.GuidedTour
  alias JidoStudio.Naming
  alias JidoStudio.Onboarding.StarterAgent
  alias JidoStudio.ProductMetrics
  alias JidoStudio.ScopeQuery

  @impl true
  def mount(_params, _session, socket) do
    agents =
      AgentRegistry.list_agents(
        jido_instance: socket.assigns[:jido_instance],
        scope: socket.assigns[:cluster_scope]
      )

    product_agents = StarterAgent.product_agents(agents)
    {starter_agent, starter_reason} = StarterAgent.pick(product_agents)

    starter_launch_path =
      starter_launch_path(
        socket.assigns.prefix,
        starter_agent,
        socket.assigns[:runtime_key],
        socket.assigns[:cluster_node_param]
      )

    {:ok,
     socket
     |> assign(:page_title, "Guide")
     |> assign(:tour_flows, GuidedTour.flows())
     |> assign(:starter_agent, starter_agent)
     |> assign(:starter_reason, starter_reason)
     |> assign(:starter_launch_path, starter_launch_path)}
  end

  @impl true
  def handle_event("tour_metric", params, socket) do
    {:noreply, GuidedTour.track_metric(socket, params)}
  end

  @impl true
  def handle_event("open_starter_agent", %{"path" => path} = params, socket)
      when is_binary(path) do
    :ok =
      ProductMetrics.onboarding_starter_opened(socket,
        source: "guide_starter_card",
        mode: normalize_mode(params["mode"], "guide"),
        starter_slug: normalize_optional_string(params["starter_slug"]),
        starter_module: normalize_optional_string(params["starter_module"])
      )

    {:noreply, push_navigate(socket, to: path)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header
        title="Guide"
        subtitle="How do you get value from Studio in under five minutes?"
      >
        <:actions>
          <.badge variant={:default}>runtime:{@runtime_key || "default"}</.badge>
          <.badge variant={:info}>node:{@cluster_node_param || "all"}</.badge>
        </:actions>
      </.page_header>

      <.tour_metric_bridge />

      <.card class="py-3">
        <p class="text-xs text-js-text-muted">
          What this page is for: choose a guided workflow, follow in-product coachmarks, and
          complete setup, interaction, and triage paths without leaving Studio.
        </p>
      </.card>

      <div class="grid grid-cols-1 xl:grid-cols-2 gap-4">
        <.card>
          <h2 class="text-sm font-semibold text-js-text">Why Discovered Counts Can Be High</h2>
          <p class="mt-2 text-xs text-js-text-muted">
            Studio separates discovered modules from running instances, so module counts are often
            higher than currently active runtime processes.
          </p>
          <ul class="mt-3 space-y-1.5 text-xs text-js-text-muted">
            <li><span class="text-js-text">Discovered modules:</span> compiled agent modules.</li>
            <li><span class="text-js-text">Running instances:</span> started processes right now.</li>
            <li>
              <span class="text-js-text">Active instances:</span> running instances in your filters.
            </li>
            <li><span class="text-js-text">Scope:</span> `runtime` + `node` change all counts.</li>
          </ul>
        </.card>

        <.card>
          <h2 class="text-sm font-semibold text-js-text">Starter Agent</h2>
          <%= if @starter_agent do %>
            <p class="mt-2 text-xs text-js-text">
              {display_agent_name(@starter_agent)}
            </p>
            <p class="mt-1 text-xs text-js-text-muted">
              Why this starter: {@starter_reason}
            </p>
            <button
              type="button"
              phx-click="open_starter_agent"
              phx-value-path={@starter_launch_path}
              phx-value-mode="guide_card"
              phx-value-starter_slug={@starter_agent.slug || ""}
              phx-value-starter_module={
                if(is_atom(@starter_agent.module), do: inspect(@starter_agent.module), else: "")
              }
              class="mt-3 inline-flex items-center rounded-md bg-js-primary px-3 py-1.5 text-xs font-medium text-js-primary-foreground hover:brightness-110"
            >
              Open Starter In Agents
            </button>
            <p class="mt-2 text-[11px] text-js-text-subtle">
              This opens the module with `start=1`; you still confirm Start Instance manually.
            </p>
          <% else %>
            <p class="mt-2 text-xs text-js-text-muted">
              {@starter_reason}
            </p>
            <.link
              navigate={starter_launch_path(@prefix, nil, @runtime_key, @cluster_node_param)}
              class="mt-3 inline-flex items-center rounded-md border border-js-border px-3 py-1.5 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Open Agents
            </.link>
          <% end %>
        </.card>
      </div>

      <div class="grid grid-cols-1 xl:grid-cols-3 gap-4">
        <.card
          :for={flow <- @tour_flows}
          data-tour-id="guide-flow-card"
          data-js-tour-flow={flow.key}
          class="flex flex-col gap-4"
        >
          <div class="space-y-2">
            <div class="flex items-center justify-between gap-2">
              <h2 class="text-sm font-semibold text-js-text">{flow.label}</h2>
              <.badge variant={:default}>{flow.duration_minutes} min</.badge>
            </div>
            <p class="text-xs text-js-text-muted">{flow.description}</p>
            <p class="text-[11px] text-js-text-subtle">
              {length(flow.steps)} steps
            </p>
          </div>

          <ol class="space-y-1.5 text-xs text-js-text-muted">
            <li :for={{step, index} <- Enum.with_index(flow.steps, 1)}>
              {index}. {step.title}
            </li>
          </ol>

          <div class="mt-auto space-y-2">
            <p data-js-tour-status class="text-[11px] text-js-text-subtle">
              Not started
            </p>
            <div class="flex flex-wrap gap-2">
              <button
                type="button"
                data-js-tour-start={flow.key}
                class="inline-flex items-center rounded-md bg-js-primary px-3 py-1.5 text-xs font-medium text-js-primary-foreground hover:brightness-110"
              >
                Start Tour
              </button>
              <button
                type="button"
                data-js-tour-resume={flow.key}
                class="hidden inline-flex items-center rounded-md border border-js-border px-3 py-1.5 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
              >
                Resume
              </button>
              <button
                type="button"
                data-js-tour-replay={flow.key}
                class="hidden inline-flex items-center rounded-md border border-js-border px-3 py-1.5 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
              >
                Replay
              </button>
            </div>
          </div>
        </.card>
      </div>
    </div>
    """
  end

  defp starter_launch_path(prefix, %{slug: slug}, runtime_key, node_param) when is_binary(slug) do
    ScopeQuery.with_scope_query("#{prefix}/agents/#{slug}?start=1", runtime_key, node_param)
  end

  defp starter_launch_path(prefix, _starter_agent, runtime_key, node_param) do
    ScopeQuery.with_scope_query("#{prefix}/agents", runtime_key, node_param)
  end

  defp display_agent_name(%{name: name}) when is_binary(name), do: Naming.humanize(name)
  defp display_agent_name(%{slug: slug}) when is_binary(slug), do: Naming.humanize(slug)
  defp display_agent_name(_), do: "Starter Agent"

  defp normalize_mode(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      normalized -> normalized
    end
  end

  defp normalize_mode(_value, fallback), do: fallback

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil
end
