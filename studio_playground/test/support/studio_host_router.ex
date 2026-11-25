defmodule StudioPlaygroundWeb.StudioHostRouter do
  @moduledoc false
  use Phoenix.Router

  import JidoStudio.Router
  import Phoenix.LiveView.Router, only: [fetch_live_flash: 2]

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_query_params
    plug :fetch_session
    plug :fetch_live_flash
    plug :studio_nonce
  end

  scope "/operations" do
    pipe_through :browser

    jido_studio("/inspect",
      showcase: true,
      csp_nonce_assign_key: %{style: :studio_style_nonce, script: :studio_script_nonce},
      on_mount: [__MODULE__]
    )

    jido_studio("/readonly",
      live_session_name: :readonly_studio,
      csp_nonce_assign_key: :studio_style_nonce,
      jido: StudioPlayground.AgentsTestRuntime,
      partition: "review"
    )
  end

  def on_mount(:default, _params, session, socket) do
    access =
      case session["studio_test_access"] do
        "allowed" ->
          :all

        "forbidden" ->
          {:forbidden, "/login"}

        "disconnect_only" ->
          if Phoenix.LiveView.connected?(socket), do: {:forbidden, "/login"}, else: :read_only

        _ ->
          :read_only
      end

    {:cont, JidoStudio.Access.put(socket, access)}
  end

  defp studio_nonce(conn, _opts) do
    conn
    |> assign(:studio_style_nonce, "style-nonce")
    |> assign(:studio_script_nonce, "script-nonce")
    |> put_resp_header(
      "content-security-policy",
      "style-src 'nonce-style-nonce'; script-src 'nonce-script-nonce'"
    )
  end
end
