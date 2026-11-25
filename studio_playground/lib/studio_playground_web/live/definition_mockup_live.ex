defmodule StudioPlaygroundWeb.DefinitionMockupLive do
  @moduledoc false
  use StudioPlaygroundWeb, :live_view

  alias JidoStudio.Components
  alias StudioPlayground.DemoCounter.{Increment, IncrementAction}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Demo counter definition",
       increment_type: Increment.type(),
       action_name: IncrementAction.name()
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="studio-definition-mockup" class="studio-agent-page">
      <nav aria-label="Agent breadcrumb">
        <.link class="studio-instance-link" href={~p"/studio/agents/demo-counter"}>
          <span aria-hidden="true">←</span> demo-counter instance
        </.link>
      </nav>

      <Components.page_header title="Demo counter" subtitle="Agent definition">
        <:actions>
          <Components.badge>Builder mockup</Components.badge>
        </:actions>
      </Components.page_header>

      <div class="definition-workspace">
        <aside class="definition-palette" aria-labelledby="definition-palette-title">
          <h2 id="definition-palette-title">Node palette</h2>
          <ul>
            <li class="definition-signal"><.node_type icon="hero-bolt" label="Signal" /></li>
            <li class="definition-route">
              <.node_type icon="hero-arrows-right-left" label="Route" />
            </li>
            <li class="definition-action"><.node_type icon="hero-play" label="Action" /></li>
            <li class="definition-state"><.node_type icon="hero-circle-stack" label="State" /></li>
            <li class="definition-reply"><.node_type icon="hero-paper-airplane" label="Reply" /></li>
          </ul>
        </aside>

        <section class="definition-canvas" aria-labelledby="definition-canvas-title">
          <header class="definition-canvas-header">
            <h2 id="definition-canvas-title">Definition canvas</h2>
            <code>demo-counter</code>
          </header>
          <p id="definition-flow-description" class="sr-only">
            The increment signal matches a route that runs the increment action.
            The route uses the action output to update count and send a reply.
          </p>
          <div
            class="definition-viewport"
            role="region"
            tabindex="0"
            aria-label="Agent definition graph"
            aria-describedby="definition-flow-description"
          >
            <div class="definition-graph">
              <article class="definition-node definition-signal definition-port-out">
                <.node_type icon="hero-bolt" label="Signal" />
                <h3><.identifier value={@increment_type} /></h3>
                <p><code>amount</code> · integer <span class="whitespace-nowrap">1–10</span></p>
                <p>Default <code>1</code></p>
              </article>
              <div class="definition-wire" aria-hidden="true"></div>
              <article class="definition-node definition-route definition-port-in definition-port-out">
                <.node_type icon="hero-arrows-right-left" label="Route" />
                <h3>Match signal type</h3>
                <p>Pass the payload to the action.</p>
              </article>
              <div class="definition-wire" aria-hidden="true"></div>
              <article class="definition-node definition-action definition-selected definition-port-in definition-port-out">
                <.node_type icon="hero-play" label="Action" />
                <h3><.identifier value={@action_name} /></h3>
                <p>Add <code>amount</code> to <code>state.count</code>.</p>
              </article>
              <div class="definition-fork" aria-hidden="true">
                <span class="definition-branch definition-branch-state"></span>
                <span class="definition-branch definition-branch-reply"></span>
              </div>
              <div class="definition-outputs">
                <article class="definition-node definition-state definition-port-in">
                  <.node_type icon="hero-circle-stack" label="State" />
                  <h3>Commit <code>count</code></h3>
                  <p>Integer · starts at <code>0</code></p>
                </article>
                <article class="definition-node definition-reply definition-port-in">
                  <.node_type icon="hero-paper-airplane" label="Reply" />
                  <h3><.identifier value="demo.counter.updated" /></h3>
                  <p>Payload · <code>count</code></p>
                </article>
              </div>
            </div>
          </div>
        </section>

        <aside class="definition-inspector" aria-labelledby="definition-inspector-title">
          <h2 id="definition-inspector-title">Inspector</h2>
          <header class="definition-action">
            <.node_type icon="hero-play" label="Selected action" />
            <p><.identifier value={@action_name} /></p>
          </header>
          <dl>
            <div>
              <dt>Input</dt>
              <dd><code>amount</code><span>Integer · 1–10</span></dd>
            </div>
            <div>
              <dt>Reads</dt>
              <dd><code>state.count</code><span>Current count</span></dd>
            </div>
            <div>
              <dt>Output</dt>
              <dd><code>count</code><span>Integer</span></dd>
            </div>
            <div>
              <dt>Output destinations</dt>
              <dd>State commit and reply payload</dd>
            </div>
          </dl>
        </aside>
      </div>
    </div>
    """
  end

  attr :icon, :string, required: true
  attr :label, :string, required: true

  defp node_type(assigns) do
    ~H"""
    <span class="definition-node-type">
      <span class="definition-node-icon" aria-hidden="true"><.icon name={@icon} /></span>
      {@label}
    </span>
    """
  end

  attr :value, :string, required: true

  defp identifier(assigns) do
    ~H"""
    <code><span :for={part <- Regex.split(~r/(?<=[._])/, @value)}>{part}<wbr /></span></code>
    """
  end
end
