defmodule StudioPlaygroundWeb.DemoAgentController do
  @moduledoc false
  use StudioPlaygroundWeb, :controller

  def on_mount(:default, params, %{"studio_path" => path}, socket) do
    action = %{label: "Start demo agent", path: JidoStudio.Mount.path(path, "/agents/demo", %{})}

    definition = %{
      label: "Goliath definition",
      path: JidoStudio.Mount.path(path, "/definitions/goliath", %{})
    }

    socket =
      Phoenix.Component.assign(socket,
        studio_agents_action: action,
        studio_agents_definition: definition
      )

    if socket.assigns.live_action == :instance and params["agent_id"] == "demo-counter" do
      socket =
        socket
        |> JidoStudio.Access.put(:all)
        |> Phoenix.Component.assign(
          :studio_definition_path,
          JidoStudio.Mount.path(path, "/agents/demo-counter/definition", %{})
        )
        |> Phoenix.Component.assign(:studio_signal_actions, [
          %{
            agent: StudioPlayground.DemoCounter,
            signal: StudioPlayground.DemoCounter.Increment,
            label: "Increment counter",
            reply_fields: [:count]
          }
        ])

      {:cont, socket}
    else
      {:cont, socket}
    end
  end

  def create(conn, _params) do
    conn =
      case StudioPlayground.DemoAgents.start_demo() do
        :ok ->
          conn

        {:error, _reason} ->
          put_flash(conn, :studio_agents_error, "Could not start the demo agent.")
      end

    conn
    |> put_status(:see_other)
    |> redirect(to: ~p"/studio/agents")
  end
end
