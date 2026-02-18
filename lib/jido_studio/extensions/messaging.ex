defmodule JidoStudio.Extensions.Messaging do
  @moduledoc """
  Optional Studio extension for jido_messaging room visibility.
  """

  @behaviour JidoStudio.Extension

  @impl true
  def id, do: :jido_messaging

  @impl true
  def installed?, do: JidoStudio.Messaging.package_available?()

  @impl true
  def routes do
    [
      %{path: "/messaging/rooms", live_view: JidoStudio.MessagingRoomsLive, action: :index}
    ]
  end

  @impl true
  def nav_sections do
    [
      %{
        id: :messaging,
        label: "Messaging",
        items: [
          %{path: "/messaging/rooms", label: "Rooms", icon: "messaging"}
        ]
      }
    ]
  end
end
