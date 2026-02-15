defmodule JidoStudio.Layouts do
  @moduledoc false
  use Phoenix.Component

  import Phoenix.HTML

  @doc false
  def studio(assigns) do
    workbench_mode? = workbench_mode?(assigns[:current_path], assigns[:prefix])

    assigns =
      assigns
      |> assign(:workbench_mode?, workbench_mode?)
      |> assign(:main_class, main_class(workbench_mode?))

    ~H"""
    <!DOCTYPE html>
    <html lang="en" class="h-full overflow-hidden">
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <meta name="csrf-token" content={Phoenix.Controller.get_csrf_token()} />
        <title>{assigns[:page_title] || "Jido Studio"}</title>
        <style>
          <%= raw(JidoStudio.Assets.css()) %>
        </style>
      </head>
      <body class="h-full overflow-hidden">
        <script>
          (function() {
            var sidebarState = localStorage.getItem('jido-studio-sidebar-state') || 'expanded';
            var theme = localStorage.getItem('jido-studio-theme') || 'dark';

            document.addEventListener('DOMContentLoaded', function() {
              var wrapper = document.getElementById('studio-wrapper');
              if (wrapper) wrapper.setAttribute('data-sidebar-state', sidebarState);
              document.documentElement.setAttribute('data-theme', theme);
            });

            window.jidoStudio = {
              toggleSidebar: function() {
                var wrapper = document.getElementById('studio-wrapper');
                if (!wrapper) return;
                var current = wrapper.getAttribute('data-sidebar-state');
                var next = current === 'expanded' ? 'collapsed' : 'expanded';
                wrapper.setAttribute('data-sidebar-state', next);
                localStorage.setItem('jido-studio-sidebar-state', next);
              },
              toggleTheme: function() {
                var current = document.documentElement.getAttribute('data-theme') || 'dark';
                var next = current === 'dark' ? 'light' : 'dark';
                document.documentElement.setAttribute('data-theme', next);
                localStorage.setItem('jido-studio-theme', next);
              }
            };
          })();
        </script>
        <div
          id="studio-wrapper"
          class="group flex h-[100dvh] max-h-[100dvh] overflow-hidden"
          data-sidebar-state="expanded"
        >
          <.sidebar current_path={@current_path} prefix={@prefix} />
          <main class={@main_class}>
            {@inner_content}
          </main>
        </div>
        <script
          :if={@host_app_js_path}
          defer
          phx-track-static
          type="text/javascript"
          src={@host_app_js_path}
        >
        </script>
        <script>
          <%= raw(JidoStudio.Assets.js()) %>
        </script>
      </body>
    </html>
    """
  end

  defp sidebar(assigns) do
    ~H"""
    <aside class="flex flex-col h-full min-h-0 bg-js-sidebar-bg border-r border-js-sidebar-border overflow-hidden
                   w-[220px] group-data-[sidebar-state=collapsed]:w-[48px]
                   transition-[width] duration-200 ease-linear">
      <%!-- SidebarHeader --%>
      <div class="flex items-center justify-between p-3 border-b border-js-sidebar-border">
        <div class="flex items-center gap-2 overflow-hidden">
          <Lucideicons.bot class="w-5 h-5 shrink-0 text-js-primary" />
          <span class="text-sm font-semibold text-js-sidebar-foreground whitespace-nowrap group-data-[sidebar-state=collapsed]:hidden">
            Jido Studio
          </span>
        </div>
        <button
          onclick="window.jidoStudio.toggleSidebar()"
          class="p-1 rounded text-js-text-muted hover:text-js-sidebar-foreground hover:bg-js-sidebar-accent shrink-0 group-data-[sidebar-state=collapsed]:hidden"
          aria-label="Toggle sidebar"
        >
          <Lucideicons.panel_left class="w-4 h-4" />
        </button>
      </div>

      <%!-- Expand button visible only when collapsed --%>
      <button
        onclick="window.jidoStudio.toggleSidebar()"
        class="hidden group-data-[sidebar-state=collapsed]:flex items-center justify-center p-2 mx-1 mt-2 rounded text-js-text-muted hover:text-js-sidebar-foreground hover:bg-js-sidebar-accent"
        aria-label="Expand sidebar"
      >
        <Lucideicons.panel_right class="w-4 h-4" />
      </button>

      <%!-- SidebarContent --%>
      <div class="flex-1 min-h-0 overflow-y-auto js-scroll py-2">
        <div>
          <div class="px-3 py-1.5 text-xs font-medium text-js-text-subtle uppercase tracking-wider group-data-[sidebar-state=collapsed]:hidden">
            Navigation
          </div>
          <nav class="space-y-0.5 mt-1">
            <.nav_item
              path="/agents"
              label="Agents"
              current_path={@current_path}
              prefix={@prefix}
              icon="agents"
            />
            <.nav_item
              path="/registry"
              label="Registry"
              current_path={@current_path}
              prefix={@prefix}
              icon="registry"
            />
            <.nav_item
              path="/threads"
              label="Threads"
              current_path={@current_path}
              prefix={@prefix}
              icon="threads"
            />
            <.nav_item
              path="/traces"
              label="Traces"
              current_path={@current_path}
              prefix={@prefix}
              icon="traces"
            />
          </nav>
        </div>
      </div>

      <%!-- SidebarFooter --%>
      <div class="border-t border-js-sidebar-border p-2">
        <.nav_item
          path="/settings"
          label="Settings"
          current_path={@current_path}
          prefix={@prefix}
          icon="settings"
        />

        <button
          onclick="window.jidoStudio.toggleTheme()"
          class="relative flex items-center gap-3 px-3 py-2 mx-2 rounded-lg text-sm text-js-text-muted hover:text-js-sidebar-foreground hover:bg-js-sidebar-accent w-[calc(100%-16px)]"
          aria-label="Toggle theme"
        >
          <Lucideicons.sun class="w-[18px] h-[18px] shrink-0 js-theme-icon-sun" />
          <Lucideicons.moon class="w-[18px] h-[18px] shrink-0 js-theme-icon-moon" />
          <span class="whitespace-nowrap group-data-[sidebar-state=collapsed]:hidden js-theme-label-dark">
            Light Mode
          </span>
          <span class="whitespace-nowrap group-data-[sidebar-state=collapsed]:hidden js-theme-label-light">
            Dark Mode
          </span>
        </button>

        <div class="mx-3 mt-2 pt-2 border-t border-js-sidebar-border group-data-[sidebar-state=collapsed]:hidden">
          <div class="text-[11px] text-js-text-subtle leading-tight">jido version:</div>
          <div class="text-[11px] text-js-text-muted font-mono leading-tight mt-0.5">
            {jido_version()}
          </div>
        </div>
      </div>
    </aside>
    """
  end

  defp nav_item(assigns) do
    full_path = assigns.prefix <> assigns.path
    current = assigns.current_path || ""
    active = current == full_path or String.starts_with?(current, full_path <> "/")
    assigns = assign(assigns, :active, active)
    assigns = assign(assigns, :full_path, full_path)

    ~H"""
    <a
      href={@full_path}
      class={"relative flex items-center gap-3 px-3 py-2 mx-2 rounded-lg text-sm #{if @active, do: "bg-js-sidebar-accent text-js-sidebar-accent-foreground", else: "text-js-text-muted hover:text-js-sidebar-foreground hover:bg-js-sidebar-accent"}"}
    >
      <span
        :if={@active}
        class="absolute left-0 top-1/2 -translate-y-1/2 w-0.5 h-4 bg-js-primary rounded-r"
      />
      <.nav_icon name={@icon} />
      <span class="whitespace-nowrap group-data-[sidebar-state=collapsed]:hidden">{@label}</span>
    </a>
    """
  end

  defp nav_icon(%{name: "agents"} = assigns) do
    ~H"""
    <Lucideicons.users class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "registry"} = assigns) do
    ~H"""
    <Lucideicons.zap class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "threads"} = assigns) do
    ~H"""
    <Lucideicons.git_branch class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "traces"} = assigns) do
    ~H"""
    <Lucideicons.activity class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "settings"} = assigns) do
    ~H"""
    <Lucideicons.settings class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp jido_version do
    case Application.spec(:jido, :vsn) do
      nil -> JidoStudio.version()
      vsn -> List.to_string(vsn)
    end
  end

  defp main_class(true) do
    "js-main-workbench flex-1 min-w-0 min-h-0 overflow-y-auto overflow-x-hidden lg:overflow-hidden lg:flex lg:flex-col bg-js-bg"
  end

  defp main_class(false) do
    "flex-1 min-w-0 min-h-0 overflow-y-auto overflow-x-hidden bg-js-bg"
  end

  defp workbench_mode?(current_path, prefix) do
    relative_path =
      current_path
      |> normalize_path()
      |> strip_prefix(prefix)

    case String.split(String.trim_leading(relative_path, "/"), "/", trim: true) do
      ["agents", _slug, _instance_id] -> true
      _ -> false
    end
  end

  defp normalize_path(path) when is_binary(path) and path != "", do: path
  defp normalize_path(_), do: "/"

  defp strip_prefix(path, prefix) when is_binary(prefix) and prefix != "" do
    prefix = String.trim_trailing(prefix, "/")

    if String.starts_with?(path, prefix) do
      stripped = String.replace_prefix(path, prefix, "")
      if stripped == "", do: "/", else: stripped
    else
      path
    end
  end

  defp strip_prefix(path, _prefix), do: path
end
