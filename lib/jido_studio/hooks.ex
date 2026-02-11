defmodule JidoStudio.Hooks do
  @moduledoc false

  import Phoenix.Component
  import Phoenix.LiveView, only: [attach_hook: 4]

  def on_mount(:default, _params, session, socket) do
    resolver = Map.get(session, "resolver", JidoStudio.Resolver.Default)
    csp_nonce_assign_key = Map.get(session, "csp_nonce_assign_key")
    prefix = Map.get(session, "prefix", "")
    jido_instance = Map.get(session, "jido_instance")
    host_app_js_path = Map.get(session, "host_app_js_path", "/assets/app.js")

    socket =
      socket
      |> assign(:resolver, resolver)
      |> assign(:csp_nonce_assign_key, csp_nonce_assign_key)
      |> assign(:jido_instance, jido_instance)
      |> assign(:host_app_js_path, host_app_js_path)
      |> assign(:studio_version, JidoStudio.version())
      |> assign(:page_title, "Jido Studio")
      |> assign(:current_path, "")
      |> assign(:prefix, prefix)
      |> attach_hook(:set_current_path, :handle_params, fn _params, uri, socket ->
        path = URI.parse(uri).path || ""
        {:cont, assign(socket, :current_path, path)}
      end)

    {:cont, socket}
  end
end
