defmodule JidoStudio.TestEndpoint do
  use Phoenix.Endpoint, otp_app: :jido_studio

  @session_options [
    store: :cookie,
    key: "_jido_studio_key",
    signing_salt: "studio-test"
  ]

  socket "/live", Phoenix.LiveView.Socket, websocket: [connect_info: [session: @session_options]]

  plug Plug.Session, @session_options
  plug JidoStudio.TestRouter
end
