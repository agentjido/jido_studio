defmodule JidoStudio.Hooks do
  @moduledoc false

  alias JidoStudio.Cluster.Scope
  alias JidoStudio.RuntimeScope
  alias JidoStudio.Telemetry

  import Phoenix.Component
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:default, params, session, socket) do
    resolver = Map.get(session, "resolver", JidoStudio.Resolver.Default)
    csp_nonce_assign_key = Map.get(session, "csp_nonce_assign_key")
    prefix = Map.get(session, "prefix", "")
    default_jido_instance = Map.get(session, "jido_instance")
    runtime_options = RuntimeScope.runtime_options(default_jido_instance)
    selected_runtime_key = RuntimeScope.default_runtime_key(runtime_options)
    runtime_key = runtime_query_key(selected_runtime_key, runtime_options, nil)
    runtime_module = RuntimeScope.runtime_module_for_key(runtime_options, selected_runtime_key)
    host_app_js_path = Map.get(session, "host_app_js_path", "/assets/app.js")
    extension_nav_sections = Map.get(session, "extension_nav_sections", [])

    socket =
      socket
      |> assign(:resolver, resolver)
      |> assign(:csp_nonce_assign_key, csp_nonce_assign_key)
      |> assign(:default_jido_instance, default_jido_instance)
      |> assign(:jido_instance, runtime_module || default_jido_instance)
      |> assign(:runtime_options, runtime_options)
      |> assign(:runtime_key, runtime_key)
      |> assign(:runtime_scope_warning, nil)
      |> assign(:host_app_js_path, host_app_js_path)
      |> assign(:extension_nav_sections, extension_nav_sections)
      |> assign(:studio_version, JidoStudio.version())
      |> assign(:page_title, "Jido Studio")
      |> assign(:current_path, "")
      |> assign(:route_params, normalize_params(params))
      |> assign(:current_query, %{})
      |> assign(:prefix, prefix)
      |> assign(:cluster_enabled?, Scope.enabled?())
      |> assign(:cluster_scope, Scope.default_scope())
      |> assign(:cluster_node_param, Scope.query_param_for_scope(Scope.default_scope()))
      |> assign(:cluster_nodes, Scope.dropdown_options())
      |> assign(:cluster_scope_warning, nil)
      |> attach_hook(:set_current_context, :handle_params, fn params, uri, socket ->
        parsed_uri = URI.parse(uri)
        query = decode_query(parsed_uri.query)
        requested_node = query["node"] || params["node"]
        node_param = Scope.normalize_node_param(requested_node)
        scope = Scope.scope_from_node_param(node_param)
        node_warning = node_scope_warning(requested_node, node_param)

        runtime_options = RuntimeScope.runtime_options(socket.assigns[:default_jido_instance])
        requested_runtime = query["runtime"] || params["runtime"]

        selected_runtime_key =
          RuntimeScope.normalize_runtime_key(requested_runtime, runtime_options)

        runtime_key = runtime_query_key(selected_runtime_key, runtime_options, requested_runtime)

        runtime_module =
          RuntimeScope.runtime_module_for_key(runtime_options, selected_runtime_key) ||
            socket.assigns[:default_jido_instance]

        runtime_warning =
          RuntimeScope.runtime_warning(requested_runtime, selected_runtime_key, runtime_options)

        :ok = Scope.put_process_node_param(node_param)
        :ok = RuntimeScope.put_process_runtime_key(runtime_key, runtime_options)

        current_query =
          query
          |> Map.put("node", node_param)
          |> maybe_put_runtime_query(runtime_key)

        emit_scope_selection_events(
          socket.assigns[:runtime_key],
          runtime_key,
          socket.assigns[:cluster_node_param],
          node_param,
          parsed_uri.path || ""
        )

        {:cont,
         socket
         |> assign(:current_path, parsed_uri.path || "")
         |> assign(:route_params, normalize_params(params))
         |> assign(:current_query, current_query)
         |> assign(:jido_instance, runtime_module)
         |> assign(:runtime_options, runtime_options)
         |> assign(:runtime_key, runtime_key)
         |> assign(:runtime_scope_warning, runtime_warning)
         |> assign(:cluster_scope, scope)
         |> assign(:cluster_node_param, node_param)
         |> assign(:cluster_nodes, Scope.dropdown_options())
         |> assign(:cluster_scope_warning, node_warning)}
      end)

    {:cont, socket}
  end

  defp decode_query(nil), do: %{}

  defp decode_query(query) when is_binary(query) do
    URI.decode_query(query)
  rescue
    _ -> %{}
  end

  defp normalize_params(params) when is_map(params), do: params
  defp normalize_params(_), do: %{}

  defp runtime_query_key(selected_runtime_key, runtime_options, requested_runtime) do
    requested_runtime = normalize_optional_string(requested_runtime)

    cond do
      length(runtime_options) > 1 ->
        selected_runtime_key

      requested_runtime ->
        selected_runtime_key

      true ->
        nil
    end
  end

  defp maybe_put_runtime_query(query, runtime_key) when is_map(query) do
    case runtime_key do
      key when is_binary(key) and key != "" -> Map.put(query, "runtime", key)
      _ -> Map.delete(query, "runtime")
    end
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(_), do: nil

  defp node_scope_warning(nil, _node_param), do: nil
  defp node_scope_warning("", _node_param), do: nil
  defp node_scope_warning("all", _node_param), do: nil

  defp node_scope_warning(requested_node, "all") when is_binary(requested_node) do
    "Selected node #{requested_node} is unavailable. Showing all nodes."
  end

  defp node_scope_warning(_requested_node, _node_param), do: nil

  defp emit_scope_selection_events(previous_runtime, runtime_key, previous_node, node_param, path) do
    if normalize_optional_string(previous_runtime) != normalize_optional_string(runtime_key) do
      Telemetry.execute([:scope, :runtime_selected], %{count: 1}, %{
        runtime: runtime_key,
        path: path
      })
    end

    if Scope.normalize_node_param(previous_node) != Scope.normalize_node_param(node_param) do
      Telemetry.execute([:scope, :node_selected], %{count: 1}, %{
        node: Scope.normalize_node_param(node_param),
        runtime: runtime_key,
        path: path
      })
    end
  end
end
