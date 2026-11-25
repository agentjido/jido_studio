defmodule JidoStudio.Access do
  @moduledoc """
  Defines Studio access for a user authenticated by the host application.

  Set the access level in a host LiveView `on_mount` hook. Studio redirects
  forbidden users before it mounts a page. The default level is `:read_only`.
  Studio handlers that change runtime or stored data must check `:action`
  permission on the server before performing the change.
  """

  alias Phoenix.LiveView.Socket

  @type level :: :read_only | :all | {:forbidden, String.t()}
  @type permission :: :read | :action

  @doc "Sets Studio access on the LiveView socket."
  @spec put(Socket.t(), level()) :: Socket.t()
  def put(%Socket{} = socket, level) when level in [:all, :read_only] do
    Phoenix.Component.assign(socket, :jido_studio_access, level)
  end

  def put(%Socket{} = socket, {:forbidden, "/" <> _ = path}) do
    Phoenix.Component.assign(socket, :jido_studio_access, {:forbidden, path})
  end

  @doc "Returns whether the socket can view Studio or perform an action."
  @spec allowed?(Socket.t(), permission()) :: boolean()
  def allowed?(%Socket{} = socket, :read), do: level(socket) in [:read_only, :all]
  def allowed?(%Socket{} = socket, :action), do: level(socket) == :all

  @doc false
  def level(%Socket{assigns: assigns}), do: Map.get(assigns, :jido_studio_access, :read_only)
end
