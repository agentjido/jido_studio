defmodule JidoStudio.PathSegmentsTest do
  use ExUnit.Case, async: true

  alias JidoStudio.PathSegments

  test "round trips standard path segments" do
    value = "configured_agent_1"

    assert value
           |> PathSegments.encode()
           |> PathSegments.decode() == value
  end

  test "encodes slash-bearing values as opaque path-safe tokens" do
    value = "configured_agent_1/react_worker"
    encoded = PathSegments.encode(value)

    refute encoded =~ "/"
    refute encoded =~ "%2F"
    assert PathSegments.decode(encoded) == value
  end
end
