defmodule JidoStudio.Layouts do
  @moduledoc false
  use Phoenix.Component

  alias JidoStudio.Cluster.Scope
  alias JidoStudio.GuidedTour
  alias JidoStudio.ScopeQuery

  import Phoenix.HTML

  @doc false
  def studio(assigns) do
    workbench_mode? =
      workbench_mode?(assigns[:current_path], assigns[:prefix], assigns[:route_params])

    extension_nav_sections = List.wrap(assigns[:extension_nav_sections])

    assigns =
      assigns
      |> assign(:workbench_mode?, workbench_mode?)
      |> assign(:main_class, main_class(workbench_mode?))
      |> assign(:nav_sections, nav_sections(extension_nav_sections))
      |> assign(:cluster_enabled?, assigns[:cluster_enabled?] != false)
      |> assign(:cluster_node_param, assigns[:cluster_node_param] || "all")
      |> assign(:cluster_nodes, assigns[:cluster_nodes] || Scope.dropdown_options())
      |> assign(:cluster_scope_warning, assigns[:cluster_scope_warning])
      |> assign(:runtime_options, assigns[:runtime_options] || [])
      |> assign(:runtime_key, assigns[:runtime_key])
      |> assign(:runtime_scope_warning, assigns[:runtime_scope_warning])
      |> assign(:runtime_selector_visible?, runtime_selector_visible?(assigns[:runtime_options]))
      |> assign(
        :runtime_label,
        runtime_label(assigns[:runtime_options], assigns[:runtime_key], assigns[:jido_instance])
      )
      |> assign(
        :cluster_status_label,
        cluster_status_label(assigns[:cluster_nodes], assigns[:cluster_scope_warning])
      )

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
            var BASE_MAIN_CLASS = 'flex-1 min-w-0 min-h-0 overflow-y-auto overflow-x-hidden bg-js-bg';
            var WORKBENCH_MAIN_CLASS = 'js-main-workbench flex-1 min-w-0 min-h-0 overflow-y-auto overflow-x-hidden lg:overflow-hidden lg:flex lg:flex-col bg-js-bg';

            function safeGet(key, fallback) {
              try {
                return localStorage.getItem(key) || fallback;
              } catch (_error) {
                return fallback;
              }
            }

            function safeSet(key, value) {
              try {
                localStorage.setItem(key, value);
              } catch (_error) {
                // ignore storage failures
              }
            }

            var sidebarState = safeGet('jido-studio-sidebar-state', 'expanded');
            var advancedScopeState = safeGet('jido-studio-advanced-scope-state', 'collapsed');
            var theme = safeGet('jido-studio-theme', 'dark');

            function normalizePath(path) {
              return typeof path === 'string' && path !== '' ? path : '/';
            }

            function stripPrefix(path, prefix) {
              if (typeof prefix !== 'string' || prefix === '') return path;
              var normalizedPrefix = prefix.replace(/\/+$/, '');
              if (normalizedPrefix === '') return path;

              if (path.indexOf(normalizedPrefix) === 0) {
                var stripped = path.slice(normalizedPrefix.length);
                return stripped === '' ? '/' : stripped;
              }

              return path;
            }

            function isWorkbenchPath() {
              var wrapper = document.getElementById('studio-wrapper');
              var prefix = wrapper ? (wrapper.getAttribute('data-prefix') || '') : '';
              var relativePath = stripPrefix(normalizePath(window.location.pathname), prefix);
              var segments = relativePath.replace(/^\/+/, '').split('/').filter(Boolean);

              return segments.length >= 3 && segments[0] === 'agents';
            }

            function applyMainMode() {
              var main = document.getElementById('studio-main');
              if (!main) return;
              main.className = isWorkbenchPath() ? WORKBENCH_MAIN_CLASS : BASE_MAIN_CLASS;
            }

            function applyChromeState() {
              var wrapper = document.getElementById('studio-wrapper');
              if (wrapper) {
                wrapper.setAttribute('data-sidebar-state', sidebarState);
                wrapper.setAttribute('data-advanced-scope-state', advancedScopeState);
              }
              document.documentElement.setAttribute('data-theme', theme);
              applyMainMode();
            }

            // Apply theme immediately to avoid flash on refresh.
            document.documentElement.setAttribute('data-theme', theme);
            applyChromeState();
            document.addEventListener('DOMContentLoaded', applyChromeState);
            window.addEventListener('pageshow', applyChromeState);
            window.addEventListener('phx:page-loading-stop', applyChromeState);
            window.addEventListener('popstate', applyChromeState);

            window.jidoStudio = {
              toggleSidebar: function() {
                var wrapper = document.getElementById('studio-wrapper');
                if (!wrapper) return;
                var current = wrapper.getAttribute('data-sidebar-state');
                var next = current === 'expanded' ? 'collapsed' : 'expanded';
                sidebarState = next;
                wrapper.setAttribute('data-sidebar-state', next);
                safeSet('jido-studio-sidebar-state', next);
              },
              toggleTheme: function() {
                var current = document.documentElement.getAttribute('data-theme') || 'dark';
                var next = current === 'dark' ? 'light' : 'dark';
                theme = next;
                document.documentElement.setAttribute('data-theme', next);
                safeSet('jido-studio-theme', next);
              },
              setClusterNode: function(nodeValue) {
                var url = new URL(window.location.href);
                url.searchParams.set('node', nodeValue || 'all');
                window.location.assign(url.toString());
              },
              setRuntime: function(runtimeKey) {
                var url = new URL(window.location.href);
                if (runtimeKey && runtimeKey !== '') {
                  url.searchParams.set('runtime', runtimeKey);
                } else {
                  url.searchParams.delete('runtime');
                }
                window.dispatchEvent(new CustomEvent('jido-studio:runtime-selection-changed', {
                  detail: { runtime: runtimeKey || null }
                }));
                window.location.assign(url.toString());
              },
              toggleAdvancedScope: function() {
                var wrapper = document.getElementById('studio-wrapper');
                if (!wrapper) return;
                var current = wrapper.getAttribute('data-advanced-scope-state');
                var next = current === 'expanded' ? 'collapsed' : 'expanded';
                advancedScopeState = next;
                wrapper.setAttribute('data-advanced-scope-state', next);
                safeSet('jido-studio-advanced-scope-state', next);
                if (next === 'expanded') {
                  window.dispatchEvent(new CustomEvent('jido-studio:advanced-scope-opened'));
                }
              }
            };
          })();
        </script>
        <div
          id="studio-wrapper"
          class="group flex h-[100dvh] max-h-[100dvh] overflow-hidden"
          data-sidebar-state="expanded"
          data-advanced-scope-state="collapsed"
          data-prefix={@prefix}
          data-js-tour-catalog={GuidedTour.flows_json()}
        >
          <.sidebar
            current_path={@current_path}
            prefix={@prefix}
            nav_sections={@nav_sections}
            cluster_enabled?={@cluster_enabled?}
            cluster_nodes={@cluster_nodes}
            cluster_node_param={@cluster_node_param}
            cluster_status_label={@cluster_status_label}
            cluster_scope_warning={@cluster_scope_warning}
            runtime_options={@runtime_options}
            runtime_key={@runtime_key}
            runtime_scope_warning={@runtime_scope_warning}
            runtime_selector_visible?={@runtime_selector_visible?}
            runtime_label={@runtime_label}
          />
          <main id="studio-main" class={@main_class}>
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

      <div class="px-3 py-2 border-b border-js-sidebar-border group-data-[sidebar-state=collapsed]:hidden">
        <label class="text-[11px] uppercase tracking-wider text-js-text-subtle">
          Scope
        </label>

        <div class="mt-1 rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5">
          <div class="text-[10px] uppercase tracking-wide text-js-text-subtle">Runtime</div>
          <div class="mt-0.5 text-xs text-js-text truncate">{@runtime_label || "Not configured"}</div>
        </div>

        <div :if={@runtime_selector_visible?} class="mt-2">
          <label
            for="studio-runtime-scope"
            class="text-[10px] uppercase tracking-wide text-js-text-subtle"
          >
            Runtime Selector
          </label>
          <select
            id="studio-runtime-scope"
            onchange="window.jidoStudio.setRuntime(this.value)"
            class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1 text-xs text-js-text"
          >
            <option
              :for={option <- @runtime_options}
              value={option.key}
              selected={option.key == @runtime_key}
            >
              {option.label}
            </option>
          </select>
        </div>

        <button
          :if={@cluster_enabled?}
          type="button"
          onclick="window.jidoStudio.toggleAdvancedScope()"
          class="mt-2 inline-flex items-center gap-1 rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
        >
          <Lucideicons.sliders_horizontal class="w-3.5 h-3.5" /> Advanced Scope
        </button>

        <div
          :if={@cluster_enabled?}
          class="hidden group-data-[advanced-scope-state=expanded]:block mt-2 space-y-2"
        >
          <label
            for="studio-cluster-scope"
            class="text-[10px] uppercase tracking-wide text-js-text-subtle"
          >
            Cluster Node
          </label>
          <select
            id="studio-cluster-scope"
            onchange="window.jidoStudio.setClusterNode(this.value)"
            class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1 text-xs text-js-text"
          >
            <option
              :for={option <- @cluster_nodes}
              value={option.value}
              selected={option.value == @cluster_node_param}
            >
              {option.label}
            </option>
          </select>

          <div class={[
            "inline-flex items-center rounded-full px-2 py-0.5 text-[11px]",
            if(@cluster_scope_warning,
              do: "bg-js-warning/15 text-js-warning",
              else: "bg-js-muted text-js-text-muted"
            )
          ]}>
            {@cluster_status_label}
          </div>

          <p :if={@cluster_scope_warning} class="text-[11px] leading-4 text-js-warning">
            {@cluster_scope_warning}
          </p>
        </div>

        <p :if={@runtime_scope_warning} class="mt-2 text-[11px] leading-4 text-js-warning">
          {@runtime_scope_warning}
        </p>
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
        <div :for={section <- @nav_sections} class={if section.id == :core, do: "", else: "mt-4"}>
          <div class="px-3 py-1.5 text-xs font-medium text-js-text-subtle uppercase tracking-wider group-data-[sidebar-state=collapsed]:hidden">
            {section.label}
          </div>
          <nav class="space-y-0.5 mt-1">
            <.nav_item
              :for={item <- section.items}
              path={item.path}
              label={item.label}
              current_path={@current_path}
              prefix={@prefix}
              icon={item.icon}
              cluster_node_param={@cluster_node_param}
              runtime_key={@runtime_key}
            />
          </nav>
        </div>
      </div>

      <%!-- SidebarFooter --%>
      <div class="border-t border-js-sidebar-border p-2">
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
    full_path =
      assigns.prefix
      |> Kernel.<>(assigns.path)
      |> normalize_nav_item_path()

    current = normalize_nav_item_path(assigns.current_path || "")
    root_item? = normalize_nav_item_path(assigns.path) == "/"

    active =
      if root_item? do
        current == full_path
      else
        current == full_path or String.starts_with?(current, full_path <> "/")
      end

    href =
      ScopeQuery.with_scope_query(
        full_path,
        assigns.runtime_key,
        assigns.cluster_node_param || "all"
      )

    assigns = assign(assigns, :active, active)
    assigns = assign(assigns, :href, href)

    ~H"""
    <a
      href={@href}
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

  defp nav_icon(%{name: "home"} = assigns) do
    ~H"""
    <Lucideicons.house class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "agents"} = assigns) do
    ~H"""
    <Lucideicons.users class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "guide"} = assigns) do
    ~H"""
    <Lucideicons.compass class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "catalog"} = assigns) do
    ~H"""
    <Lucideicons.book_open class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "activity"} = assigns) do
    ~H"""
    <Lucideicons.activity class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "diagnostics"} = assigns) do
    ~H"""
    <Lucideicons.stethoscope class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "settings"} = assigns) do
    ~H"""
    <Lucideicons.settings class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "about"} = assigns) do
    ~H"""
    <Lucideicons.info class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(%{name: "messaging"} = assigns) do
    ~H"""
    <Lucideicons.message_circle class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_icon(assigns) do
    ~H"""
    <Lucideicons.zap class="w-[18px] h-[18px] shrink-0" />
    """
  end

  defp nav_sections(extension_nav_sections) do
    [core_nav_section() | normalize_nav_sections(extension_nav_sections)]
  end

  defp core_nav_section do
    %{
      id: :core,
      label: "Navigation",
      items: [
        %{path: "/", label: "Home", icon: "home"},
        %{path: "/guide", label: "Guide", icon: "guide"},
        %{path: "/agents", label: "Agents", icon: "agents"},
        %{path: "/catalog", label: "Catalog", icon: "catalog"},
        %{path: "/activity", label: "Activity", icon: "activity"},
        %{path: "/diagnostics", label: "Diagnostics", icon: "diagnostics"},
        %{path: "/settings", label: "Settings", icon: "settings"},
        %{path: "/about", label: "About", icon: "about"}
      ]
    }
  end

  defp normalize_nav_sections(sections) when is_list(sections) do
    Enum.flat_map(sections, &normalize_nav_section/1)
  end

  defp normalize_nav_sections(_), do: []

  defp normalize_nav_section(section) when is_map(section) do
    id = Map.get(section, :id) || Map.get(section, "id")
    label = Map.get(section, :label) || Map.get(section, "label")
    items = Map.get(section, :items) || Map.get(section, "items")

    if (is_atom(id) or is_binary(id)) and is_binary(label) and is_list(items) do
      normalized_items =
        items
        |> Enum.flat_map(&normalize_nav_item/1)

      if normalized_items == [] do
        []
      else
        [%{id: id, label: label, items: normalized_items}]
      end
    else
      []
    end
  end

  defp normalize_nav_section(_), do: []

  defp normalize_nav_item(item) when is_map(item) do
    path = Map.get(item, :path) || Map.get(item, "path")
    label = Map.get(item, :label) || Map.get(item, "label")
    icon = Map.get(item, :icon) || Map.get(item, "icon")

    if is_binary(path) and is_binary(label) and is_binary(icon) do
      [%{path: path, label: label, icon: icon}]
    else
      []
    end
  end

  defp normalize_nav_item(_), do: []

  defp cluster_status_label(options, warning) when is_list(options) do
    node_count = Enum.count(options, &(&1[:value] != "all"))

    cond do
      warning ->
        "Scope fallback"

      node_count <= 1 ->
        "Single Node"

      true ->
        "Cluster: #{node_count} nodes"
    end
  end

  defp cluster_status_label(_, _), do: "Single Node"

  defp runtime_selector_visible?(options) when is_list(options), do: length(options) > 1
  defp runtime_selector_visible?(_), do: false

  defp runtime_label(options, runtime_key, jido_instance)

  defp runtime_label(options, runtime_key, _jido_instance) when is_list(options) do
    Enum.find_value(options, fn
      %{key: ^runtime_key, label: label} when is_binary(label) -> label
      _ -> nil
    end)
  end

  defp runtime_label(_, _, module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
  end

  defp runtime_label(_, _, _), do: nil

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

  defp workbench_mode?(current_path, prefix, route_params) do
    relative_path =
      current_path
      |> normalize_path()
      |> strip_prefix(prefix)

    path_match? =
      case String.split(String.trim_leading(relative_path, "/"), "/", trim: true) do
        ["agents", _slug, _instance_id] -> true
        _ -> false
      end

    path_match? or workbench_route_params?(route_params)
  end

  defp workbench_route_params?(params) when is_map(params) do
    slug = Map.get(params, "slug") || Map.get(params, :slug)
    instance_id = Map.get(params, "instance_id") || Map.get(params, :instance_id)
    is_binary(slug) and slug != "" and is_binary(instance_id) and instance_id != ""
  end

  defp workbench_route_params?(_), do: false

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

  defp normalize_nav_item_path(path) when is_binary(path) do
    normalized =
      path
      |> String.trim()
      |> case do
        "" -> "/"
        value -> value
      end

    if normalized == "/" do
      "/"
    else
      String.trim_trailing(normalized, "/")
    end
  end

  defp normalize_nav_item_path(_), do: "/"
end
