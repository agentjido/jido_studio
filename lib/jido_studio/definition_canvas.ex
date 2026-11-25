defmodule JidoStudio.DefinitionCanvas do
  @moduledoc false

  use Phoenix.Component

  attr :graph, :map, required: true
  attr :mode, :string, required: true
  attr :nested, :string, default: nil
  attr :selection, :any, required: true
  attr :canvas_path, :any, required: true

  def canvas(assigns) do
    nodes = Map.new(assigns.graph.nodes, &{&1.id, &1})

    selected_node =
      if match?({"node", _}, assigns.selection), do: nodes[elem(assigns.selection, 1)]

    selected_edge =
      case assigns.selection do
        {"connection", id} -> Enum.find(assigns.graph.edges, &(&1.id == id))
        _node -> nil
      end

    connections =
      if selected_node do
        Enum.filter(assigns.graph.edges, &(selected_node.id in [&1.from, &1.to]))
      else
        assigns.graph.edges
      end

    assigns =
      assign(assigns,
        nodes: nodes,
        selected_node: selected_node,
        selected_edge: selected_edge,
        connections: connections,
        id: "studio-graph-" <> Base.url_encode64(assigns.graph.key, padding: false)
      )

    ~H"""
    <jido-definition-canvas id={@id} class="studio-definition-canvas">
      <header class="studio-canvas-header">
        <div>
          <nav class="studio-canvas-modes" aria-label="Canvas views">
            <.link patch={@canvas_path.("route", nil)} aria-current={if @mode == "route", do: "page"}>
              Route
            </.link>
            <.link
              patch={@canvas_path.("topology", nil)}
              aria-current={if @mode == "topology", do: "page"}
            >
              Topology
            </.link>
          </nav>
          <h2 id="studio-canvas-title">{@graph.title}</h2>
          <.link :if={@nested} patch={@canvas_path.("route", nil)}>← Back to route</.link>
        </div>
        <div class="studio-canvas-tools" role="group" aria-label="Canvas zoom">
          <button type="button" data-canvas-action="out" aria-label="Zoom out">−</button>
          <output data-canvas-zoom>100%</output>
          <button type="button" data-canvas-action="in" aria-label="Zoom in">+</button>
          <button type="button" data-canvas-action="fit">Fit</button>
        </div>
      </header>

      <div class="studio-canvas-layout">
        <div
          class="studio-canvas-viewport"
          data-canvas-viewport
          tabindex="0"
          role="region"
          aria-labelledby="studio-canvas-title"
          aria-describedby="studio-canvas-help"
        >
          <div data-canvas-frame>
            <div class="studio-canvas-scene" data-canvas-scene data-graph-kind={@graph.kind}>
              <svg class="studio-canvas-wires" aria-hidden="true">
                <defs>
                  <marker
                    id={"#{@id}-arrow"}
                    viewBox="0 0 8 8"
                    refX="8"
                    refY="4"
                    markerWidth="7"
                    markerHeight="7"
                    orient="auto"
                  >
                    <path d="M 0 0 L 8 4 L 0 8 z" fill="context-stroke" />
                  </marker>
                </defs>
                <g :for={connection <- @graph.edges}>
                  <path
                    class="studio-canvas-wire"
                    data-from={connection.from}
                    data-to={connection.to}
                    data-highlight={
                      if connection.active || @selection == {"connection", connection.id}, do: "true"
                    }
                    marker-end={"url(##{@id}-arrow)"}
                  />
                  <text :if={label = wire_label(@graph.kind, connection)} data-wire-label>
                    {label}
                  </text>
                </g>
              </svg>
              <div class="studio-canvas-columns">
                <div :for={column <- @graph.columns} class="studio-canvas-column">
                  <button
                    :for={node <- column}
                    type="button"
                    class="studio-canvas-node"
                    data-canvas-node={node.id}
                    data-kind={node.kind}
                    phx-click="inspect_canvas_item"
                    phx-value-kind="node"
                    phx-value-id={node.id}
                    aria-pressed={to_string(@selection == {"node", node.id})}
                  >
                    <span>{node.kind}</span>
                    <strong>{node.title}</strong>
                    <small :if={node.caption}>{node.caption}</small>
                  </button>
                </div>
              </div>
            </div>
          </div>
        </div>

        <aside
          id="studio-canvas-inspector"
          class="studio-canvas-inspector"
          aria-label="Canvas inspector"
          aria-live="polite"
        >
          <section :if={node = @selected_node}>
            <span class="studio-canvas-inspector-kind">{node.kind}</span>
            <h3>{node.title}</h3>
            <code :if={node.detail}>{node.detail}</code>
            <.link :if={node.open_flow} patch={@canvas_path.("route", node.open_flow)}>Open flow →</.link>
            <.fields fields={node.fields} />
            <ul :if={node.options != []} class="studio-canvas-options">
              <li :for={option <- node.options}>
                <strong>{Phoenix.Naming.humanize(option["name"])}</strong>
                <span :if={option["event"]}><code>{option["event"]}</code></span>
                <span :if={option["after_ms"]}>After {duration(option["after_ms"])}</span>
                <code :if={option["condition"]}>{option["condition"]}</code>
                <.fields fields={option["inputs"]} />
              </li>
            </ul>
          </section>

          <section :if={connection = @selected_edge}>
            <span class="studio-canvas-inspector-kind">Connection</span>
            <h3><code>{connection.label}</code></h3>
            <dl class="studio-definition-fields">
              <div>
                <dt>From</dt><dd>{@nodes[connection.from].title}</dd>
              </div>
              <div>
                <dt>To</dt><dd>{@nodes[connection.to].title}</dd>
              </div>
              <div :if={connection.detail}>
                <dt>Detail</dt><dd><code>{connection.detail}</code></dd>
              </div>
            </dl>
          </section>

          <details :if={@connections != []} class="studio-canvas-connections" open>
            <summary>Connections · {length(@connections)}</summary>
            <ul>
              <li :for={connection <- @connections}>
                <button
                  type="button"
                  phx-click="inspect_canvas_item"
                  phx-value-kind="connection"
                  phx-value-id={connection.id}
                  aria-pressed={to_string(@selection == {"connection", connection.id})}
                >
                  <strong>{connection.label}</strong>
                  <span>{@nodes[connection.from].title} → {@nodes[connection.to].title}</span>
                </button>
              </li>
            </ul>
          </details>
        </aside>
      </div>
      <p id="studio-canvas-help">
        Drag the background or use the arrow keys to pan. Use + and − to zoom.
      </p>
    </jido-definition-canvas>
    """
  end

  attr :fields, :list, required: true

  defp fields(assigns) do
    ~H"""
    <dl :if={@fields != []} class="studio-definition-fields">
      <div :for={field <- @fields}>
        <dt><code>{field["name"]}</code></dt>
        <dd><code>{field["value"]}</code></dd>
      </div>
    </dl>
    """
  end

  defp duration(ms) when rem(ms, 60_000) == 0, do: "#{div(ms, 60_000)} min"
  defp duration(ms), do: "#{ms} ms"

  defp wire_label(:topology, %{detail: "broadcast"}), do: "Broadcast"
  defp wire_label(:flow, %{to: "output", label: label}), do: label
  defp wire_label(_kind, _connection), do: nil
end
