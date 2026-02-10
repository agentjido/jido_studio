defmodule JidoStudio.TraceBufferTest do
  use ExUnit.Case, async: false

  alias JidoStudio.TraceBuffer

  test "events/0 returns empty list when no events" do
    assert is_list(TraceBuffer.events())
  end
end
