defmodule StudioPlaygroundWeb.GoliathDefinitionLive do
  @moduledoc false
  use StudioPlaygroundWeb, :live_view

  import JidoStudio.DefinitionComponents, only: [definition: 1]
  alias JidoStudio.DefinitionGraph

  @snapshot_path Path.expand("../../../priv/definitions/goliath.json", __DIR__)
  @external_resource @snapshot_path
  @definition @snapshot_path |> File.read!() |> Jason.decode!()

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket,
       page_title: "Goliath definition",
       definition: @definition,
       routes: @definition["routes"],
       filter: to_form(%{"query" => ""}, as: :signals)
     )}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    %{"routes" => routes, "featured" => featured} = socket.assigns.definition
    default_signal = List.first(featured)["signal"]
    default_route = Enum.find(routes, List.first(routes), &(&1["signal"] == default_signal))
    route = Enum.find(routes, default_route, &(&1["signal"] == params["signal"]))
    view = if params["view"] in ~w(topology resources canvas), do: params["view"], else: "routes"
    mode = if params["graph"] == "topology", do: "topology", else: "route"

    graph =
      if view == "canvas", do: DefinitionGraph.build(@definition, route, mode, params["flow"])

    selection =
      case graph do
        %{key: key, nodes: [first | _]} ->
          case socket.assigns do
            %{canvas_graph: %{key: ^key}, canvas_selection: previous} -> previous
            _ -> {"node", first.id}
          end

        _ ->
          nil
      end

    {:noreply,
     assign(socket,
       route: route,
       view: view,
       canvas_mode: mode,
       canvas_graph: graph,
       canvas_selection: selection
     )}
  end

  @impl true
  def handle_event("filter_signals", %{"signals" => %{"query" => query}}, socket)
      when is_binary(query) do
    query = String.slice(query, 0, 150)
    term = query |> String.trim() |> String.downcase()

    routes =
      Enum.filter(socket.assigns.definition["routes"], fn route ->
        String.contains?(String.downcase(route["signal"]), term)
      end)

    {:noreply, assign(socket, routes: routes, filter: to_form(%{"query" => query}, as: :signals))}
  end

  def handle_event("inspect_canvas_item", %{"kind" => kind, "id" => id}, socket) do
    items =
      case {kind, socket.assigns.canvas_graph} do
        {"node", %{nodes: nodes}} -> nodes
        {"connection", %{edges: edges}} -> edges
        _ -> []
      end

    socket =
      if Enum.any?(items, &(&1.id == id)),
        do: assign(socket, :canvas_selection, {kind, id}),
        else: socket

    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.definition
      definition={@definition}
      route={@route}
      routes={@routes}
      filter={@filter}
      view={@view}
      view_path={&view_path(&1, @route["signal"])}
      signal_path={&view_path("routes", &1)}
      canvas_mode={@canvas_mode}
      canvas_graph={@canvas_graph}
      canvas_selection={@canvas_selection}
      canvas_path={&canvas_path/3}
    />
    """
  end

  defp view_path("routes", signal), do: ~p"/studio/definitions/goliath?#{%{signal: signal}}"

  defp view_path(view, signal),
    do: ~p"/studio/definitions/goliath?#{%{signal: signal, view: view}}"

  defp canvas_path(mode, flow, signal) do
    params = %{signal: signal, view: "canvas", graph: mode}
    params = if flow, do: Map.put(params, :flow, flow), else: params
    ~p"/studio/definitions/goliath?#{params}"
  end
end
