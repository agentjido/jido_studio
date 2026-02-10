defmodule JidoStudio.Hooks do
  @moduledoc false

  import Phoenix.LiveView
  import Phoenix.Component

  def on_mount(:default, _params, session, socket) do
    resolver = Map.get(session, "resolver", JidoStudio.Resolver.Default)
    csp_nonce_assign_key = Map.get(session, "csp_nonce_assign_key")

    socket =
      socket
      |> assign(:resolver, resolver)
      |> assign(:csp_nonce_assign_key, csp_nonce_assign_key)
      |> assign(:studio_version, JidoStudio.version())
      |> assign(:page_title, "Jido Studio")

    {:cont, socket}
  end
end
