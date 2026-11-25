defmodule JidoStudio.Layouts do
  @moduledoc false
  use Phoenix.Component

  alias JidoStudio.Mount

  @external_resource Path.join(__DIR__, "shell.css")
  @external_resource Path.join(__DIR__, "shell.js")
  @external_resource Path.join(__DIR__, "components.css")
  @external_resource Path.join(__DIR__, "definition.css")
  @external_resource Path.join(__DIR__, "definition_canvas.css")
  @external_resource Path.join(__DIR__, "definition_canvas.js")
  @shell_styles File.read!(Path.join(__DIR__, "shell.css")) <>
                  File.read!(Path.join(__DIR__, "components.css")) <>
                  File.read!(Path.join(__DIR__, "definition.css")) <>
                  File.read!(Path.join(__DIR__, "definition_canvas.css"))
  @shell_script File.read!(Path.join(__DIR__, "shell.js")) <>
                  File.read!(Path.join(__DIR__, "definition_canvas.js"))

  @doc false
  def studio(assigns) do
    assigns =
      assign(assigns,
        shell_styles: @shell_styles,
        shell_script: @shell_script,
        jido_version: Application.spec(:jido, :vsn)
      )

    ~H"""
    <div id="studio-shell">
      <style id="studio-shell-styles" nonce={@studio_nonces.style}>
        <%= Phoenix.HTML.raw(@shell_styles) %>
      </style>
      <aside id="studio-sidebar">
        <%!-- The controls keep browser-owned state across LiveView patches. --%>
        <div id="studio-sidebar-header" phx-update="ignore">
          <p id="studio-brand">
            <.icon name="bot" />
            <span class="studio-sidebar-label">Jido Studio</span>
          </p>
          <button
            id="studio-sidebar-toggle"
            type="button"
            aria-label="Toggle sidebar"
            aria-expanded="true"
            aria-controls="studio-sidebar"
            title="Toggle sidebar"
          >
            <.icon name="panel" />
          </button>
        </div>

        <div id="studio-scope" class="studio-sidebar-label">
          <p>Scope</p>
          <span>Host application</span>
          <%= if @live_action in [:agents, :instance, :turns, :definition] do %>
            <span :if={@studio_runtime.jido}>Runtime · {inspect(@studio_runtime.jido)}</span>
            <span :if={@studio_runtime.partition}>Partition · {@studio_runtime.partition}</span>
          <% else %>
            <span :if={@live_action != :overview && @studio_scope["runtime"]}>
              Runtime · {@studio_scope["runtime"]}
            </span>
            <span :if={@live_action != :overview && @studio_scope["node"]}>
              Node · {@studio_scope["node"]}
            </span>
          <% end %>
        </div>

        <nav id="studio-navigation" aria-label="Studio navigation">
          <p class="studio-sidebar-label">Navigation</p>
          <.nav_link
            href={Mount.path(@studio_path, "", @studio_scope)}
            active={@live_action == :overview}
            label="Overview"
            icon="home"
          />
          <.nav_link
            href={Mount.path(@studio_path, "/agents", @studio_scope)}
            active={@live_action in [:agents, :instance, :turns, :definition]}
            label="Agents"
            icon="agents"
          />
          <div :if={@studio_showcase} class="studio-navigation-section">
            <p class="studio-sidebar-label">Design</p>
            <.nav_link
              href={Mount.path(@studio_path, "/components", @studio_scope)}
              active={@live_action == :components}
              label="Components"
              icon="components"
            />
          </div>
        </nav>

        <div id="studio-sidebar-footer" phx-update="ignore">
          <button
            id="studio-theme-toggle"
            type="button"
            aria-label="Light theme"
            aria-pressed="false"
            title="Toggle light or dark theme"
          >
            <.icon name="sun" />
            <.icon name="moon" />
            <span class="studio-sidebar-label studio-show-in-dark">Light Mode</span>
            <span class="studio-sidebar-label studio-show-in-light">Dark Mode</span>
          </button>
          <p :if={@jido_version} id="studio-jido-version" class="studio-sidebar-label">
            Jido version <code>{List.to_string(@jido_version)}</code>
          </p>
        </div>
      </aside>
      <main id="studio-main">
        {@inner_content}
      </main>
      <script id="studio-shell-script" nonce={@studio_nonces.script}>
        <%= Phoenix.HTML.raw(@shell_script) %>
      </script>
    </div>
    """
  end

  defp nav_link(assigns) do
    ~H"""
    <a href={@href} aria-current={if @active, do: "page"} aria-label={@label} title={@label}>
      <.icon name={@icon} />
      <span class="studio-sidebar-label">{@label}</span>
    </a>
    """
  end

  attr :name, :string, required: true

  defp icon(assigns) do
    ~H"""
    <svg
      class={"studio-icon studio-icon-#{@name}"}
      viewBox="0 0 24 24"
      fill="none"
      stroke="currentColor"
      stroke-width="1.75"
      stroke-linecap="round"
      stroke-linejoin="round"
      aria-hidden="true"
    >
      <%= case @name do %>
        <% "bot" -> %>
          <rect x="4" y="8" width="16" height="12" rx="3" />
          <path d="M12 8V4m-2 0h4M4 13H2m18 0h2M8 16h8" />
          <circle cx="9" cy="12" r=".75" fill="currentColor" stroke="none" />
          <circle cx="15" cy="12" r=".75" fill="currentColor" stroke="none" />
        <% "panel" -> %>
          <rect x="3" y="4" width="18" height="16" rx="2" />
          <path d="M10 4v16" />
        <% "home" -> %>
          <path d="m3 11 9-8 9 8M5 10v10h14V10m-10 10v-7h6v7" />
        <% "agents" -> %>
          <rect x="3" y="4" width="18" height="6" rx="2" />
          <rect x="3" y="14" width="18" height="6" rx="2" />
          <path d="M7 7h.01M7 17h.01M11 7h6m-6 10h6" />
        <% "components" -> %>
          <rect x="3" y="3" width="7" height="7" rx="1.5" />
          <rect x="14" y="3" width="7" height="7" rx="1.5" />
          <rect x="3" y="14" width="7" height="7" rx="1.5" />
          <rect x="14" y="14" width="7" height="7" rx="1.5" />
        <% "sun" -> %>
          <circle cx="12" cy="12" r="4" />
          <path d="M12 2v3m0 14v3M2 12h3m14 0h3M5 5l2 2m10 10 2 2M5 19l2-2m10-10 2-2" />
        <% "moon" -> %>
          <path d="M20.5 15.3A8.5 8.5 0 0 1 8.7 3.5a8.8 8.8 0 1 0 11.8 11.8Z" />
      <% end %>
    </svg>
    """
  end
end
