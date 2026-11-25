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

    if Application.compile_env(:studio_playground, :dev_routes, false) do
      post "/studio/agents/demo", DemoAgentController, :create

      jido_studio("/studio",
        jido: StudioPlayground.Jido,
        showcase: true,
        on_mount: [StudioPlaygroundWeb.DemoAgentController]
      )

      live_session :studio_definition_mockup,
        session:
          {JidoStudio.Mount, :session,
           ["/studio", nil, true, %{jido: StudioPlayground.Jido, partition: nil}]},
        layout: {JidoStudio.Layouts, :studio},
        on_mount: [JidoStudio.Mount] do
        live "/studio/agents/demo-counter/definition", DefinitionMockupLive, :definition
        live "/studio/definitions/goliath", GoliathDefinitionLive, :goliath_definition
      end
    else
      jido_studio("/studio", jido: StudioPlayground.Jido, showcase: true)
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", StudioPlaygroundWeb do
  #   pipe_through :api
  # end
end
