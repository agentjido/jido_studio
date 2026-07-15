defmodule StudioPlaygroundWeb.Router do
  use StudioPlaygroundWeb, :router

  import JidoStudio.Router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {StudioPlaygroundWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/", StudioPlaygroundWeb do
    pipe_through :browser

    get "/", PageController, :home

    jido_studio("/studio",
      jido_instance: StudioPlayground.Jido,
      host_app_js_path: "/assets/js/app.js"
    )
  end

  # Other scopes may use custom stacks.
  # scope "/api", StudioPlaygroundWeb do
  #   pipe_through :api
  # end
end
