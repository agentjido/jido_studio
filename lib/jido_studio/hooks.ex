defmodule JidoStudio.Hooks do
  @moduledoc false

  alias JidoStudio.Cluster.Scope

  import Phoenix.Component
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:default, params, session, socket) do
    resolver = Map.get(session, "resolver", JidoStudio.Resolver.Default)
    csp_nonce_assign_key = Map.get(session, "csp_nonce_assign_key")
    prefix = Map.get(session, "prefix", "")
    jido_instance = Map.get(session, "jido_instance")
    host_app_js_path = Map.get(session, "host_app_js_path", "/assets/app.js")
    extension_nav_sections = Map.get(session, "extension_nav_sections", [])

    socket =
      socket
      |> assign(:resolver, resolver)
      |> assign(:csp_nonce_assign_key, csp_nonce_assign_key)
      |> assign(:jido_instance, jido_instance)
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
        warning = node_scope_warning(requested_node, node_param)

        :ok = Scope.put_process_node_param(node_param)

        {:cont,
         socket
         |> assign(:current_path, parsed_uri.path || "")
         |> assign(:route_params, normalize_params(params))
         |> assign(:current_query, Map.put(query, "node", node_param))
         |> assign(:cluster_scope, scope)
         |> assign(:cluster_node_param, node_param)
         |> assign(:cluster_nodes, Scope.dropdown_options())
         |> assign(:cluster_scope_warning, warning)}
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

  defp node_scope_warning(nil, _node_param), do: nil
  defp node_scope_warning("", _node_param), do: nil
  defp node_scope_warning("all", _node_param), do: nil

  defp node_scope_warning(requested_node, "all") when is_binary(requested_node) do
    "Selected node #{requested_node} is unavailable. Showing all nodes."
  end

  defp node_scope_warning(_requested_node, _node_param), do: nil
end
