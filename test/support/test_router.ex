defmodule JidoStudio.TestRouter do
  use Phoenix.Router

  import JidoStudio.Router
  import Phoenix.LiveView.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  scope "/" do
    pipe_through :browser

    jido_studio("/studio",
      jido_instance: JidoStudio.TestJido,
      host_app_js_path: nil
    )
  end
end
