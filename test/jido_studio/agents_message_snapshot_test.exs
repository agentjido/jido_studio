defmodule JidoStudio.Agents.MessageSnapshotTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Agents.MessageSnapshot

  test "normalizes runtime thread messages" do
    runtime_status = %{
      raw_state: %{
        __strategy__: %{
          thread: %{
            entries: [
              %{
                role: :assistant,
                content: [
                  %{type: :thinking, content: "thinking block"},
                  %{type: :text, content: "hello"}
                ],
                tool_calls: [
                  %{id: "call-1", name: "weather.lookup", arguments: %{city: "Austin"}}
                ]
              },
              %{role: :tool, tool_call_id: "call-1", content: "{\"ok\":true}"}
            ]
          },
          todos: [%{id: "todo-1", content: "Check weather", status: "in_progress"}]
        }
      }
    }

    messages = MessageSnapshot.thread_messages(runtime_status)

    assert length(messages) == 2

    [tool_result, assistant] = messages

    assert tool_result.role == :tool
    assert tool_result.tool_results != []
    assert assistant.role == :assistant
    assert [%{call_id: "call-1"}] = assistant.tool_calls
  end

  test "extracts todos from strategy state" do
    runtime_status = %{
      raw_state: %{
        __strategy__: %{
          todos: [
            %{id: "todo-a", text: "Do thing", status: :pending},
            "Fallback todo"
          ]
        }
      }
    }

    todos = MessageSnapshot.todos(runtime_status)

    assert Enum.map(todos, & &1.id) == ["todo-a", "2"]
    assert Enum.map(todos, & &1.content) == ["Do thing", "Fallback todo"]
  end
end
