defmodule JidoStudio.DefinitionComponents do
  @moduledoc "Read-only LiveView components for a Jido agent definition snapshot."

  use Phoenix.Component
  import JidoStudio.Components, only: [badge: 1, page_header: 1, tabs: 1]

  alias JidoStudio.DefinitionCanvas, as: Canvas
  alias JidoStudio.DefinitionOverviewComponents, as: Overview

  attr :definition, :map, required: true
  attr :route, :map, required: true
  attr :routes, :list, required: true
  attr :filter, :map, required: true
  attr :view, :string, required: true
  attr :view_path, :any, required: true
  attr :signal_path, :any, required: true
  attr :canvas_graph, :map, default: nil
  attr :canvas_mode, :string, default: "route"
  attr :canvas_selection, :any, default: nil
  attr :canvas_path, :any, default: nil

  @doc """
  Renders a definition snapshot and the selected route.

  The signal path function receives a signal pattern and returns a LiveView patch URL.
  See `JidoStudio.DefinitionSnapshot.from_visual_map/2` for the input format.
  """
  @spec definition(map()) :: Phoenix.LiveView.Rendered.t()
  def definition(assigns) do
    ~H"""
    <div id="studio-definition">
      <.page_header title={label(@definition["name"])} subtitle={@definition["description"]}>
        <:actions>
          <.badge>Read-only definition</.badge>
        </:actions>
      </.page_header>

      <.tabs active={@view} label="Definition views">
        <:tab id="routes" label="Signal routes" patch={@view_path.("routes")} />
        <:tab id="canvas" label="Canvas" patch={@view_path.("canvas")} />
        <:tab id="topology" label="Topology" patch={@view_path.("topology")} />
        <:tab id="resources" label="Resources" patch={@view_path.("resources")} />
      </.tabs>

      <%= case @view do %>
        <% "canvas" -> %>
          <div class="studio-definition-workspace">
            <.catalog
              routes={@routes}
              total={length(@definition["routes"])}
              selected={@route["signal"]}
              filter={@filter}
              signal_path={&@canvas_path.("route", nil, &1)}
              initial_state={@definition["initial_state"]}
            />
            <Canvas.canvas
              graph={@canvas_graph}
              mode={@canvas_mode}
              nested={@canvas_graph[:nested]}
              selection={@canvas_selection}
              canvas_path={&@canvas_path.(&1, &2, @route["signal"])}
            />
          </div>
        <% "topology" -> %>
          <Overview.topology
            definition={@definition}
            signal_path={@signal_path}
            selected={@route["signal"]}
          />
        <% "resources" -> %>
          <Overview.resources definition={@definition} signal_path={@signal_path} />
        <% "routes" -> %>
          <.featured
            entries={@definition["featured"] || []}
            selected={@route["signal"]}
            signal_path={@signal_path}
          />
          <div class="studio-definition-workspace">
            <.catalog
              routes={@routes}
              total={length(@definition["routes"])}
              selected={@route["signal"]}
              filter={@filter}
              signal_path={@signal_path}
              initial_state={@definition["initial_state"]}
            />
            <.inspector definition={@definition} route={@route} view_path={@view_path} />
          </div>
      <% end %>
    </div>
    """
  end

  attr :entries, :list, required: true
  attr :selected, :string, required: true
  attr :signal_path, :any, required: true

  defp featured(assigns) do
    ~H"""
    <nav :if={@entries != []} class="studio-definition-featured" aria-label="Featured routes">
      <.link
        :for={entry <- @entries}
        patch={@signal_path.(entry["signal"])}
        aria-current={if entry["signal"] == @selected, do: "true"}
      >
        <strong>{entry["label"]}</strong>
        <span>{entry["summary"]}</span>
      </.link>
    </nav>
    """
  end

  attr :routes, :list, required: true
  attr :total, :integer, required: true
  attr :selected, :string, required: true
  attr :filter, :map, required: true
  attr :signal_path, :any, required: true
  attr :initial_state, :list, required: true

  defp catalog(assigns) do
    namespaces =
      assigns.routes
      |> Enum.group_by(fn route -> route["signal"] |> String.split(".", parts: 2) |> hd() end)
      |> Enum.sort_by(&elem(&1, 0))

    assigns = assign(assigns, :namespaces, namespaces)

    ~H"""
    <aside class="studio-definition-catalog" aria-label="Route catalog">
      <section class="studio-definition-panel" aria-labelledby="studio-definition-routes-title">
        <header class="studio-definition-panel-header">
          <h2 id="studio-definition-routes-title">All signals</h2>
          <span>{length(@routes)} / {@total}</span>
        </header>
        <.form
          for={@filter}
          id="studio-definition-filter"
          phx-change="filter_signals"
          phx-submit="filter_signals"
        >
          <label for={@filter[:query].id} class="sr-only">Find a signal</label>
          <input
            type="search"
            id={@filter[:query].id}
            name={@filter[:query].name}
            value={@filter[:query].value}
            placeholder="Find a signal"
            autocomplete="off"
            phx-debounce="150"
          />
        </.form>
        <div id="studio-definition-routes">
          <p :if={@namespaces == []} role="status">No matching signals.</p>
          <section :for={{namespace, routes} <- @namespaces}>
            <h3>{namespace}</h3>
            <ul>
              <li :for={route <- routes}>
                <.link
                  patch={@signal_path.(route["signal"])}
                  aria-current={if route["signal"] == @selected, do: "true"}
                >
                  <code>{route["signal"]}</code>
                  <span :if={route["handler"]["kind"] == "flow"} class="studio-definition-tag">
                    Flow
                  </span>
                </.link>
              </li>
            </ul>
          </section>
        </div>
      </section>
      <details :if={@initial_state != []} class="studio-definition-panel studio-definition-initial">
        <summary id="studio-definition-state-title">Initial state</summary>
        <.fields fields={@initial_state} />
      </details>
    </aside>
    """
  end

  attr :definition, :map, required: true
  attr :route, :map, required: true
  attr :view_path, :any, required: true

  defp inspector(assigns) do
    featured =
      Enum.find(assigns.definition["featured"] || [], &(&1["signal"] == assigns.route["signal"]))

    connections =
      Enum.count(
        assigns.definition["topology"]["connections"] || [],
        &(&1["signal"] == assigns.route["signal"])
      )

    assigns = assign(assigns, featured: featured, connections: connections)

    ~H"""
    <section
      :if={@route}
      id="studio-definition-inspector"
      class="studio-definition-panel"
      aria-labelledby="studio-definition-inspector-title"
    >
      <header class="studio-definition-panel-header">
        <div>
          <span>Signal route</span>
          <h2 id="studio-definition-inspector-title">
            <span :if={@featured}>{@featured["label"]}</span>
            <code :if={!@featured}>{@route["signal"]}</code>
          </h2>
          <code :if={@featured}>{@route["signal"]}</code>
        </div>
        <div class="studio-canvas-entry-links">
          <.link patch={@view_path.("canvas")}>Open canvas →</.link>
          <.link :if={@connections > 0} patch={@view_path.("topology")}>
            View signal topology →
          </.link>
        </div>
      </header>

      <div class="studio-definition-body">
        <div :if={@route["defaults"] != []}>
          <h3>Route defaults</h3>
          <.fields fields={@route["defaults"]} />
        </div>

        <.flow
          :if={flow = @definition["flows"][@route["handler"]["target"]]}
          flow={flow}
          flows={@definition["flows"]}
          parents={[@route["handler"]["target"]]}
        />

        <div class="studio-definition-blocks" aria-label="Declared route behavior">
          <div class="studio-definition-block">
            <h3>{kind(@route["handler"]["kind"])}</h3>
            <code>{@route["handler"]["target"]}</code>
          </div>
          <div class="studio-definition-block" data-kind="state">
            <h3>Agent state</h3>
            <code :if={@route["state"]}>Commit from {@route["state"]}</code>
            <span :if={!@route["state"]}>Unchanged</span>
          </div>
          <div :if={reply = @route["reply"]} class="studio-definition-block" data-kind="reply">
            <h3>Reply</h3>
            <code>{reply["signal"]}</code>
            <span :if={reply["from"]}>From <code>{reply["from"]}</code></span>
          </div>
        </div>
      </div>
    </section>
    """
  end

  attr :flow, :map, required: true
  attr :flows, :map, required: true
  attr :parents, :list, required: true

  defp flow(assigns) do
    {layers, _names} =
      assigns.flow["components"]
      |> Enum.group_by(&(&1["level"] || 0))
      |> Enum.sort_by(&elem(&1, 0))
      |> Enum.map_reduce([], fn {level, components}, previous_names ->
        joined? =
          previous_names != [] &&
            Enum.all?(components, fn component ->
              Enum.all?(previous_names, &(&1 in component["needs"]))
            end)

        {{level, components, joined?}, Enum.map(components, & &1["name"])}
      end)

    assigns = assign(assigns, :layers, layers)

    ~H"""
    <div class="studio-definition-flow">
      <h3 class="studio-definition-flow-title">
        <span>Flow</span> {label(@flow["name"])}
      </h3>
      <div
        :for={{level, components, joined?} <- @layers}
        class="studio-definition-flow-layer"
        data-level={level}
        data-joined={if joined?, do: "true"}
      >
        <ul class="studio-definition-components">
          <li
            :for={component <- components}
            class="studio-definition-block"
            data-kind={component["kind"]}
          >
            <h4>
              <span class="studio-definition-kind">
                {kind(component["handler"]["kind"] || component["kind"])}
              </span>
              {label(component["name"])}
            </h4>
            <ul
              :if={component["needs"] != []}
              class="studio-definition-dependencies"
              aria-label="Depends on"
            >
              <li :for={name <- component["needs"]}>{label(name)}</li>
            </ul>
            <.nested_flow target={component["handler"]["target"]} flows={@flows} parents={@parents} />
            <%= if level == 0 and component["kind"] in ~w(call choice) do %>
              <details class="studio-definition-step-details">
                <summary>
                  {if component["kind"] == "choice", do: "Conditions", else: "Bindings"}
                </summary>
                <.step_details component={component} />
              </details>
            <% else %>
              <.step_details component={component} />
            <% end %>
          </li>
        </ul>
      </div>
      <div :if={@flow["output"] != []} class="studio-definition-flow-output">
        <h4>Flow output</h4>
        <.fields fields={@flow["output"]} />
      </div>
    </div>
    """
  end

  attr :component, :map, required: true

  defp step_details(assigns) do
    ~H"""
    <code :if={@component["handler"]}>{@component["handler"]["target"]}</code>
    <.fields fields={@component["inputs"]} />
    <ul :if={@component["options"] != []} class="studio-definition-options">
      <li :for={option <- @component["options"]} class="studio-definition-block">
        <h5>{label(option["name"])}</h5>
        <code :if={option["handler"]}>{option["handler"]["target"]}</code>
        <code :if={option["event"]}>{option["event"]}</code>
        <code :if={option["condition"]}>{option["condition"]}</code>
        <span :if={option["after_ms"]}>After {duration(option["after_ms"])}</span>
        <.fields fields={option["inputs"]} />
      </li>
    </ul>
    """
  end

  attr :target, :string, required: true
  attr :flows, :map, required: true
  attr :parents, :list, required: true

  defp nested_flow(assigns) do
    ~H"""
    <details
      :if={@target not in @parents && @flows[@target]}
      class="studio-definition-nested-flow"
    >
      <summary>Expand flow</summary>
      <.flow flow={@flows[@target]} flows={@flows} parents={[@target | @parents]} />
    </details>
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

  defp kind(value), do: value |> String.replace("_", " ") |> String.capitalize()
  defp label(value), do: Phoenix.Naming.humanize(value)
  defp duration(ms) when rem(ms, 60_000) == 0, do: "#{div(ms, 60_000)} min"
  defp duration(ms), do: "#{ms} ms"
end
