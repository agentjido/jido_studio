defmodule JidoStudio.MessagingTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Messaging

  defmodule Provider do
    def list_rooms do
      [
        %{id: "ops", name: "Ops", member_count: 3, status: "active", topic: "incidents"},
        %{room_id: "dev", slug: "dev-room", members: ["a", "b"]}
      ]
    end
  end

  setup do
    previous_provider = Application.get_env(:jido_studio, :messaging_room_provider)

    on_exit(fn ->
      if is_nil(previous_provider) do
        Application.delete_env(:jido_studio, :messaging_room_provider)
      else
        Application.put_env(:jido_studio, :messaging_room_provider, previous_provider)
      end
    end)

    :ok
  end

  test "uses configured provider and normalizes rooms" do
    Application.put_env(:jido_studio, :messaging_room_provider, {Provider, :list_rooms})

    assert Messaging.provider_available?()
    assert Messaging.available?()

    assert {:ok, rooms} = Messaging.list_rooms()

    assert Enum.any?(rooms, fn room ->
             room.id == "ops" and room.name == "Ops" and room.member_count == 3 and
               room.status == "active"
           end)

    assert Enum.any?(rooms, fn room ->
             room.id == "dev" and room.name == "dev-room" and room.member_count == 2 and
               room.status == nil
           end)
  end

  test "returns unavailable when no provider exists" do
    Application.delete_env(:jido_studio, :messaging_room_provider)

    assert {:error, :unavailable} = Messaging.list_rooms()
  end
end
