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
      scope path, alias: false, as: false do
        import Phoenix.LiveView.Router, only: [live: 4, live_session: 3]

        resolver = Keyword.get(opts, :resolver, JidoStudio.Resolver.Default)
        socket_path = Keyword.get(opts, :socket_path, "/live")
        csp_nonce_assign_key = Keyword.get(opts, :csp_nonce_assign_key)
        on_mount = Keyword.get(opts, :on_mount, [])

        session_args = %{
          "resolver" => resolver,
          "csp_nonce_assign_key" => csp_nonce_assign_key
        }

        live_session :jido_studio,
          session: {JidoStudio.Router, :__session__, [session_args]},
          on_mount: [{JidoStudio.Hooks, :default} | on_mount],
          root_layout: {JidoStudio.Layouts, :studio} do
          live "/", JidoStudio.AgentsLive, :index
          live "/agents", JidoStudio.AgentsLive, :index
          live "/agents/:id", JidoStudio.AgentsLive, :show
          live "/agents/:id/chat", JidoStudio.AgentsLive, :chat
          live "/actions", JidoStudio.ActionsLive, :index
          live "/actions/:id", JidoStudio.ActionsLive, :show
          live "/workflows", JidoStudio.WorkflowsLive, :index
          live "/workflows/:id", JidoStudio.WorkflowsLive, :show
          live "/signals", JidoStudio.SignalsLive, :index
          live "/traces", JidoStudio.TracesLive, :index
          live "/settings", JidoStudio.SettingsLive, :index
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
