defmodule JidoStudio.RegistryLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  @tabs ["agents", "actions", "sensors", "plugins"]

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(:page_title, "Registry")
      |> assign(:tabs, @tabs)
      |> assign(:tab, "agents")
      |> assign(:query, "")
      |> assign(:items, [])
      |> assign(:selected_slug, nil)
      |> assign(:selected_item, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = normalize_tab(params["tab"])
    query = normalize_optional_string(params["q"]) || ""
    selected_slug = normalize_optional_string(params["selected"])

    items = list_tab_items(tab, query)
    selected_item = Enum.find(items, &(&1[:slug] == selected_slug)) || List.first(items)

    {:noreply,
     socket
     |> assign(:tab, tab)
     |> assign(:query, query)
     |> assign(:items, items)
     |> assign(:selected_slug, selected_item && selected_item[:slug])
     |> assign(:selected_item, selected_item)}
  end

  @impl true
  def handle_event("search", %{"q" => query}, socket) do
    {:noreply,
     push_patch(socket,
       to: path(socket.assigns.prefix, socket.assigns.tab, query, socket.assigns.selected_slug)
     )}
  end

  @impl true
  def handle_event("select", %{"slug" => slug}, socket) do
    {:noreply,
     push_patch(socket,
       to: path(socket.assigns.prefix, socket.assigns.tab, socket.assigns.query, slug)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Registry" subtitle="Discovery-powered catalog of Jido runtime capabilities">
        <:actions>
          <form phx-change="search" class="flex items-center gap-2">
            <input
              type="text"
              name="q"
              value={@query}
              placeholder="Search registry"
              class="w-64 rounded-md border border-js-border bg-js-bg-elevated px-3 py-1.5 text-xs text-js-text focus:outline-none focus:ring-2 focus:ring-js-ring"
            />
          </form>
        </:actions>
      </.page_header>

      <div class="inline-flex rounded-lg border border-js-border p-1 bg-js-bg-elevated">
        <.link
          :for={tab <- @tabs}
          navigate={path(@prefix, tab, @query, @selected_slug)}
          class={[
            "px-3 py-1.5 rounded-md text-xs font-medium transition-colors",
            if(@tab == tab,
              do: "bg-js-card text-js-text",
              else: "text-js-text-muted hover:text-js-text"
            )
          ]}
        >
          {String.capitalize(tab)}
        </.link>
      </div>

      <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,2fr)_minmax(0,1fr)] gap-4">
        <.card class="p-0 overflow-hidden">
          <div :if={@items == []} class="p-6">
            <.empty_state
              title="No components found"
              description="Try another search or ensure Jido.Discovery has initialized for your runtime."
            />
          </div>

          <div :if={@items != []} class="divide-y divide-js-border">
            <button
              :for={item <- @items}
              type="button"
              phx-click="select"
              phx-value-slug={item[:slug]}
              class={[
                "w-full text-left px-4 py-3 transition-colors",
                if(item[:slug] == @selected_slug,
                  do: "bg-js-bg-elevated/60",
                  else: "hover:bg-js-bg-elevated/40"
                )
              ]}
            >
              <div class="flex items-center justify-between gap-3">
                <div class="min-w-0">
                  <div class="text-sm text-js-text truncate">
                    {item[:name] || inspect(item[:module])}
                  </div>
                  <div class="text-xs text-js-text-subtle font-mono truncate">
                    {inspect(item[:module])}
                  </div>
                </div>
                <.badge variant={:default}>{item[:category] || "n/a"}</.badge>
              </div>
              <p class="mt-1 text-xs text-js-text-muted line-clamp-2">{item[:description] || ""}</p>
            </button>
          </div>
        </.card>

        <.card>
          <%= if @selected_item do %>
            <div class="space-y-3 text-xs">
              <div class="text-sm font-semibold text-js-text">
                {@selected_item[:name] || inspect(@selected_item[:module])}
              </div>
              <div class="text-js-text-subtle font-mono break-all">
                {inspect(@selected_item[:module])}
              </div>
              <p class="text-js-text-muted">
                {@selected_item[:description] || "No description provided."}
              </p>

              <div class="flex flex-wrap gap-2">
                <.badge variant={:info}>slug:{@selected_item[:slug]}</.badge>
                <.badge variant={:default}>category:{@selected_item[:category] || "n/a"}</.badge>
                <.badge :for={tag <- List.wrap(@selected_item[:tags] || [])} variant={:warning}>
                  {to_string(tag)}
                </.badge>
              </div>

              <div class="pt-2 border-t border-js-border">
                <div class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-1">
                  Metadata
                </div>
                <pre class="text-xs text-js-text-muted bg-js-bg-elevated border border-js-border rounded-md p-2 whitespace-pre-wrap break-words"><%= inspect(Map.drop(@selected_item, [:description]), pretty: true, limit: 50, printable_limit: 8000) %></pre>
              </div>

              <div class="pt-2 border-t border-js-border">
                <div class="text-[11px] uppercase tracking-wider text-js-text-subtle mb-1">
                  Schema Hint
                </div>
                <pre class="text-xs text-js-text-muted bg-js-bg-elevated border border-js-border rounded-md p-2 whitespace-pre-wrap break-words"><%= schema_hint(@selected_item[:module]) %></pre>
              </div>
            </div>
          <% else %>
            <.empty_state
              title="Select a component"
              description="Choose an item from the registry list."
            />
          <% end %>
        </.card>
      </div>
    </div>
    """
  end

  defp list_tab_items("agents", query), do: list_agents(query)
  defp list_tab_items("actions", query), do: apply_discovery(:list_actions, query)
  defp list_tab_items("sensors", query), do: apply_discovery(:list_sensors, query)
  defp list_tab_items("plugins", query), do: apply_discovery(:list_plugins, query)
  defp list_tab_items(_, query), do: list_agents(query)

  defp list_agents(query) do
    agents = JidoStudio.AgentRegistry.list_discovered_agents()

    agents =
      if query != "" do
        Enum.filter(agents, fn a ->
          String.contains?(to_string(a[:name] || ""), query)
        end)
      else
        agents
      end

    Enum.sort_by(agents, &to_string(&1[:name] || ""))
  end

  defp apply_discovery(fun, query) do
    args = if query == "", do: [[]], else: [[name: query]]

    case apply(Jido.Discovery, fun, args) do
      items when is_list(items) -> Enum.sort_by(items, &to_string(&1[:name] || ""))
      _ -> []
    end
  rescue
    _ -> []
  end

  defp normalize_tab(tab) when tab in @tabs, do: tab
  defp normalize_tab(_), do: "agents"

  defp path(prefix, tab, query, selected_slug) do
    params =
      %{}
      |> maybe_put_param("tab", tab)
      |> maybe_put_param("q", normalize_optional_string(query))
      |> maybe_put_param("selected", normalize_optional_string(selected_slug))

    if map_size(params) == 0 do
      prefix <> "/registry"
    else
      prefix <> "/registry?" <> URI.encode_query(params)
    end
  end

  defp maybe_put_param(params, _key, nil), do: params
  defp maybe_put_param(params, key, value), do: Map.put(params, key, value)

  defp normalize_optional_string(value) when is_binary(value) do
    normalized = String.trim(value)
    if normalized == "", do: nil, else: normalized
  end

  defp normalize_optional_string(_), do: nil

  defp schema_hint(module) when is_atom(module) do
    cond do
      function_exported?(module, :schema, 0) ->
        inspect(apply(module, :schema, []), pretty: true, limit: 60)

      function_exported?(module, :input_schema, 0) ->
        inspect(apply(module, :input_schema, []), pretty: true, limit: 60)

      function_exported?(module, :__action_metadata__, 0) ->
        inspect(apply(module, :__action_metadata__, []), pretty: true, limit: 60)

      function_exported?(module, :__sensor_metadata__, 0) ->
        inspect(apply(module, :__sensor_metadata__, []), pretty: true, limit: 60)

      function_exported?(module, :__agent_metadata__, 0) ->
        inspect(apply(module, :__agent_metadata__, []), pretty: true, limit: 60)

      function_exported?(module, :__plugin_metadata__, 0) ->
        inspect(apply(module, :__plugin_metadata__, []), pretty: true, limit: 60)

      true ->
        "No explicit schema exported"
    end
  rescue
    _ -> "No explicit schema exported"
  end

  defp schema_hint(_), do: "No explicit schema exported"
end
