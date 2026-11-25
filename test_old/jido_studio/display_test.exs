defmodule JidoStudio.DisplayTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Display

  test "formats structured model metadata without duplicating provider prefixes" do
    assert Display.model_label(%{provider: :openai, id: "openai/gpt-oss-20b"}) ==
             "openai/gpt-oss-20b"

    assert Display.model_label(%{"provider" => "anthropic", "id" => "claude-sonnet-4-5"}) ==
             "anthropic:claude-sonnet-4-5"
  end

  test "formats arbitrary maps safely for display" do
    assert Display.value(%{foo: "bar"}) =~ "foo"
  end
end
