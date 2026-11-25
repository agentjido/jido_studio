defmodule JidoStudio.Router do
  @moduledoc """
  Mounts Jido Studio inside a Phoenix browser scope.
  """

  @doc """
  Mounts the Studio LiveView at the given path.

  Studio uses the host's root layout, LiveView client, and socket URL.
  Mount it behind the host's browser and authentication plugs.

  ## Options

    * `:on_mount` runs host hooks before Studio checks `JidoStudio.Access`.
    * `:csp_nonce_assign_key` reads a nonce from the HTTP connection assigns.
      Pass one atom for both assets or a map with `:style` and `:script` keys
      for separate connection assigns.
    * `:live_session_name` names the Phoenix LiveView session. Use a distinct
      atom for each mount in one router. Defaults to `:jido_studio`.
    * `:showcase` adds the component review page at `/components` under the
      mount. Defaults to `false`.
    * `:jido` selects a supervised local Jido v3 runtime by its registered name.
      It defaults to `nil`, which leaves the runtime disconnected.
    * `:partition` selects one partition in that runtime. It defaults to the
      unpartitioned scope. Set both options in the router, where the host
      controls which runtime data its users can view.

      import JidoStudio.Router

      scope "/" do
        pipe_through :browser
        jido_studio "/studio"
      end
  """
  defmacro jido_studio(path, opts \\ []) do
    quote bind_quoted: [path: path, opts: opts] do
      require Phoenix.LiveView.Router

      opts =
        Keyword.validate!(opts,
          on_mount: [],
          csp_nonce_assign_key: nil,
          live_session_name: :jido_studio,
          showcase: false,
          jido: nil,
          partition: nil
        )

      studio_path = Phoenix.Router.scoped_path(__MODULE__, path)
      studio_runtime = JidoStudio.Mount.runtime(opts[:jido], opts[:partition])

      scope path, alias: false, as: false do
        Phoenix.LiveView.Router.live_session opts[:live_session_name],
          session:
            {JidoStudio.Mount, :session,
             [studio_path, opts[:csp_nonce_assign_key], opts[:showcase], studio_runtime]},
          layout: {JidoStudio.Layouts, :studio},
          on_mount: List.wrap(opts[:on_mount]) ++ [JidoStudio.Mount] do
          Phoenix.LiveView.Router.live("/", JidoStudio.HomeLive, :overview)
          Phoenix.LiveView.Router.live("/agents", JidoStudio.AgentsLive, :agents)
          Phoenix.LiveView.Router.live("/agents/:agent_id", JidoStudio.AgentsLive, :instance)
          Phoenix.LiveView.Router.live("/agents/:agent_id/turns", JidoStudio.TurnsLive, :turns)

          if opts[:showcase] do
            Phoenix.LiveView.Router.live("/components", JidoStudio.ShowcaseLive, :components)
          end
        end
      end
    end
  end
end
