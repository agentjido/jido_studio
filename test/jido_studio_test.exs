defmodule JidoStudioTest do
  use ExUnit.Case

  test "version/0 returns a version string" do
    assert JidoStudio.version() == "0.1.0"
  end
end
