defmodule JidoStudio.PayloadFormTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Agents.PayloadForm

  test "build exposes supported primitive fields for selected action schema" do
    interaction_model = %{
      actions: [
        %{
          key: "action:add",
          schema_json: %{
            "type" => "object",
            "required" => ["a"],
            "properties" => %{
              "a" => %{"type" => "number"},
              "label" => %{"type" => "string"},
              "enabled" => %{"type" => "boolean"}
            }
          }
        }
      ],
      signals: []
    }

    form = PayloadForm.build(interaction_model, {:action, "action:add"}, ~s({"a":2}))

    assert form.supported?
    assert Enum.map(form.fields, & &1.name) == ["a", "enabled", "label"]
  end

  test "apply_fields casts numeric and returns field-level errors for invalid input" do
    interaction_model = %{
      actions: [
        %{
          key: "action:add",
          schema_json: %{
            "type" => "object",
            "required" => ["a"],
            "properties" => %{
              "a" => %{"type" => "number"},
              "count" => %{"type" => "integer"}
            }
          }
        }
      ],
      signals: []
    }

    assert {:ok, payload_json, errors} =
             PayloadForm.apply_fields(interaction_model, {:action, "action:add"}, %{
               "a" => "nope",
               "count" => "4"
             })

    assert errors["a"] == "Enter a valid number."
    assert PayloadForm.decode_payload(payload_json)["count"] == 4
  end
end
