defmodule JidoStudio.Router do
  @moduledoc """
  Provides mount points for the Jido Studio dashboard.

  ## Usage

  Import the router in your Phoenix router and mount the studio:

      import JidoStudio.Router

      scope "/" do
        pipe_through [:browser]
        jido_studio "/studio"
      end

  ## Options

    * `:resolver` — a `JidoStudio.Resolver` implementation for access control
      and customization. Defaults to `JidoStudio.Resolver.Default`.

    * `:socket_path` — the Phoenix socket path for LiveView connections.
      Defaults to `"/live"`.

    * `:csp_nonce_assign_key` — CSP nonce key(s) for securing assets.
      Can be `nil`, a single atom, or a map with `:img`, `:style`, and
      `:script` keys. Defaults to `nil`.

    * `:on_mount` — additional `on_mount` hooks to run. Useful for
      adding authentication checks.

    * `:jido_instance` — the Jido supervisor module (e.g. `MyApp.Jido`).
      Used for runtime agent discovery (listing running agents, start/stop).
      Falls back to `config :jido_studio, :jido_instance`. Defaults to `nil`.

    * `:host_app_js_path` — path to host app JavaScript that boots Phoenix LiveView.
      Defaults to `"/assets/app.js"`. Set to `nil` to skip loading host JS.

  ## Examples

  Mount with authentication:

      scope "/" do
        pipe_through [:browser, :require_authenticated_user]
        jido_studio "/studio"
      end

  Mount with a custom resolver:

      scope "/" do
        pipe_through [:browser]
        jido_studio "/studio",
          resolver: MyApp.StudioResolver,
          on_mount: [{MyAppWeb.Auth, :ensure_admin}]
      end
  """

  defmacro jido_studio(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      require Phoenix.LiveView.Router

      resolver = Keyword.get(opts, :resolver, JidoStudio.Resolver.Default)
      socket_path = Keyword.get(opts, :socket_path, "/live")
      csp_nonce_assign_key = Keyword.get(opts, :csp_nonce_assign_key)
      on_mount = Keyword.get(opts, :on_mount, [])
      host_app_js_path = Keyword.get(opts, :host_app_js_path, "/assets/app.js")

      jido_instance =
        Keyword.get_lazy(opts, :jido_instance, fn ->
          Application.compile_env(:jido_studio, :jido_instance)
        end)

      prefix =
        Phoenix.Router.scoped_path(__MODULE__, path)
        |> String.replace_suffix("/", "")

      session_args = %{
        "resolver" => resolver,
        "csp_nonce_assign_key" => csp_nonce_assign_key,
        "prefix" => prefix,
        "jido_instance" => jido_instance,
        "host_app_js_path" => host_app_js_path
      }

      scope path, alias: false, as: false do
        Phoenix.LiveView.Router.live_session :jido_studio,
          session: {JidoStudio.Router, :__session__, [session_args]},
          on_mount: [{JidoStudio.Hooks, :default} | on_mount],
          root_layout: {JidoStudio.Layouts, :studio} do
          Phoenix.LiveView.Router.live("/", JidoStudio.AgentsLive, :index)
          Phoenix.LiveView.Router.live("/agents", JidoStudio.AgentsLive, :index)
          Phoenix.LiveView.Router.live("/agents/:slug/:instance_id", JidoStudio.AgentsLive, :show)
          Phoenix.LiveView.Router.live("/agents/:slug", JidoStudio.AgentsLive, :show)
          Phoenix.LiveView.Router.live("/registry", JidoStudio.RegistryLive, :index)
          Phoenix.LiveView.Router.live("/threads", JidoStudio.ThreadsLive, :index)

          Phoenix.LiveView.Router.live(
            "/threads/:agent_slug/:instance_id/:thread_id",
            JidoStudio.ThreadsLive,
            :show
          )

          Phoenix.LiveView.Router.live("/actions", JidoStudio.ActionsLive, :index)
          Phoenix.LiveView.Router.live("/actions/:id", JidoStudio.ActionsLive, :show)
          Phoenix.LiveView.Router.live("/workflows", JidoStudio.WorkflowsLive, :index)
          Phoenix.LiveView.Router.live("/workflows/:id", JidoStudio.WorkflowsLive, :show)
          Phoenix.LiveView.Router.live("/signals", JidoStudio.SignalsLive, :index)
          Phoenix.LiveView.Router.live("/traces", JidoStudio.TracesLive, :index)
          Phoenix.LiveView.Router.live("/traces/:trace_id", JidoStudio.TracesLive, :show)
          Phoenix.LiveView.Router.live("/settings", JidoStudio.SettingsLive, :index)
        end
      end
    end
  end

  @doc false
  def __session__(conn, session_args) do
    Map.merge(session_args, %{
      "current_user" => conn.assigns[:current_user]
    })
  end
end
