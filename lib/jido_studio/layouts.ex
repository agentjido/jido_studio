defmodule JidoStudio.Layouts do
  @moduledoc false
  use Phoenix.Component

  import Phoenix.HTML

  @doc false
  def studio(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full bg-gray-950">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title><%= assigns[:page_title] || "Jido Studio" %></title>
        <style><%= raw(JidoStudio.Assets.css()) %></style>
      </head>
      <body class="h-full antialiased">
        <div class="flex h-full">
          <.sidebar current_path={@current_path} />
          <main class="flex-1 overflow-auto">
            <%= @inner_content %>
          </main>
        </div>
        <script><%= raw(JidoStudio.Assets.js()) %></script>
      </body>
    </html>
    """
  end

  defp sidebar(assigns) do
    ~H"""
    <nav class="flex flex-col w-56 bg-gray-900 border-r border-gray-800 text-gray-300">
      <div class="p-4 border-b border-gray-800">
        <span class="text-lg font-semibold text-white">Jido Studio</span>
      </div>

      <div class="flex-1 py-2 space-y-1 overflow-y-auto">
        <.nav_item path="/agents" label="Agents" current_path={@current_path} />
        <.nav_item path="/actions" label="Actions" current_path={@current_path} />
        <.nav_item path="/workflows" label="Workflows" current_path={@current_path} />
        <.nav_item path="/signals" label="Signals" current_path={@current_path} />
        <.nav_item path="/traces" label="Traces" current_path={@current_path} />
      </div>

      <div class="p-4 border-t border-gray-800 space-y-1">
        <.nav_item path="/settings" label="Settings" current_path={@current_path} />
        <div class="px-3 py-1 text-xs text-gray-500">
          v<%= JidoStudio.version() %>
        </div>
      </div>
    </nav>
    """
  end

  defp nav_item(assigns) do
    active = String.starts_with?(assigns.current_path || "", assigns.path)
    assigns = assign(assigns, :active, active)

    ~H"""
    <a
      href={@path}
      class={"block px-3 py-2 mx-2 rounded-md text-sm #{if @active, do: "bg-gray-800 text-white", else: "text-gray-400 hover:bg-gray-800 hover:text-white"}"}
    >
      <%= @label %>
    </a>
    """
  end
end
