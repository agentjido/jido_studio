defmodule JidoStudio.AccessTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Access
  alias Phoenix.LiveView.Socket

  test "only a host's explicit full grant permits actions" do
    socket = %Socket{}
    assert Access.allowed?(socket, :read)
    refute Access.allowed?(socket, :action)

    socket = Access.put(socket, :all)
    assert Access.allowed?(socket, :read)
    assert Access.allowed?(socket, :action)

    socket = Access.put(socket, {:forbidden, "/login"})
    refute Access.allowed?(socket, :read)
    refute Access.allowed?(socket, :action)
  end
end
