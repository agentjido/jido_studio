defmodule JidoStudio.Agents.MessageSnapshot do
  @moduledoc false

  @spec thread_messages(map() | [map()]) :: [map()]
  def thread_messages(runtime_status_or_entries)

  def thread_messages(entries) when is_list(entries) do
    normalize_thread_entries(entries)
  end

  def thread_messages(runtime_status) when is_map(runtime_status) do
    runtime_status
    |> thread_entries_from_status()
    |> normalize_thread_entries()
  end

  def thread_messages(_), do: []

  @spec todos(map()) :: [map()]
  def todos(runtime_status) when is_map(runtime_status) do
    strategy_state = strategy_state(runtime_status)
    details = snapshot_details(runtime_status)

    value =
      strategy_state[:todos] ||
        strategy_state["todos"] ||
        details[:todos] ||
        details["todos"]

    normalize_todos(value)
  end

  def todos(_), do: []

  @spec normalize_thread_entries([map()]) :: [map()]
  def normalize_thread_entries(entries) when is_list(entries) do
    entries
    |> Enum.with_index(1)
    |> Enum.map(fn {entry, idx} ->
      role = role(entry)
      tool_calls = normalize_tool_calls(entry[:tool_calls] || entry["tool_calls"])
      tool_results = normalize_tool_results(entry[:tool_results] || entry["tool_results"])

      %{
        id: idx,
        role: role,
        status: normalize_optional_string(entry[:status] || entry["status"]),
        content: normalize_content(entry[:content] || entry["content"]),
        tool_calls: tool_calls,
        tool_results: inferred_tool_results(role, tool_results, entry),
        metadata: normalize_metadata(entry[:metadata] || entry["metadata"])
      }
    end)
  end

  def normalize_thread_entries(_), do: []

  defp thread_entries_from_status(status) when is_map(status) do
    strategy_state = strategy_state(status)

    entries =
      strategy_state
      |> Map.get(:thread, Map.get(strategy_state, "thread"))
      |> case do
        %{entries: entries} when is_list(entries) -> entries
        %{"entries" => entries} when is_list(entries) -> entries
        _ -> []
      end

    Enum.reverse(entries)
  end

  defp thread_entries_from_status(_), do: []

  defp strategy_state(status) when is_map(status) do
    status
    |> Map.get(:raw_state, %{})
    |> Map.get(:__strategy__, %{})
  end

  defp strategy_state(_), do: %{}

  defp snapshot_details(status) when is_map(status) do
    case Map.get(status, :snapshot, %{}) do
      %{details: details} when is_map(details) -> details
      %{"details" => details} when is_map(details) -> details
      _ -> %{}
    end
  end

  defp snapshot_details(_), do: %{}

  defp role(entry) when is_map(entry) do
    case entry[:role] || entry["role"] do
      value when value in [:assistant, "assistant"] -> :assistant
      value when value in [:user, "user"] -> :user
      value when value in [:tool, "tool"] -> :tool
      value when value in [:system, "system"] -> :system
      _ -> :unknown
    end
  end

  defp role(_), do: :unknown

  defp normalize_content(content) when is_binary(content), do: content

  defp normalize_content(content) when is_list(content) do
    Enum.map(content, fn
      %{type: type} = part ->
        %{
          type: normalize_content_type(type),
          content: normalize_optional_string(part[:content] || part["content"]),
          data: part
        }

      %{"type" => type} = part ->
        %{
          type: normalize_content_type(type),
          content: normalize_optional_string(part[:content] || part["content"]),
          data: part
        }

      value when is_binary(value) ->
        %{type: :text, content: value, data: value}

      other ->
        %{type: :unknown, content: inspect(other, limit: 80), data: other}
    end)
  end

  defp normalize_content(content), do: content

  defp normalize_content_type(type) when type in [:text, "text"], do: :text
  defp normalize_content_type(type) when type in [:thinking, "thinking"], do: :thinking
  defp normalize_content_type(type) when type in [:image, "image"], do: :image
  defp normalize_content_type(_), do: :unknown

  defp normalize_tool_calls(tool_calls) when is_list(tool_calls) do
    tool_calls
    |> Enum.map(fn call ->
      %{
        call_id:
          normalize_optional_string(call[:id] || call["id"] || call[:call_id] || call["call_id"]),
        name: normalize_optional_string(call[:name] || call["name"]) || "tool",
        arguments: call[:arguments] || call["arguments"] || %{}
      }
    end)
    |> Enum.reject(&is_nil(&1.call_id))
  end

  defp normalize_tool_calls(_), do: []

  defp normalize_tool_results(results) when is_list(results) do
    Enum.map(results, fn result ->
      %{
        tool_call_id:
          normalize_optional_string(
            result[:tool_call_id] || result["tool_call_id"] || result[:id] || result["id"]
          ),
        name: normalize_optional_string(result[:name] || result["name"]) || "Result",
        status: normalize_result_status(result),
        content: result[:content] || result["content"] || result
      }
    end)
  end

  defp normalize_tool_results(_), do: []

  defp inferred_tool_results(:tool, [], entry) do
    content = entry[:content] || entry["content"]

    [
      %{
        tool_call_id: normalize_optional_string(entry[:tool_call_id] || entry["tool_call_id"]),
        name: normalize_optional_string(entry[:name] || entry["name"]) || "Result",
        status: tool_status_from_content(content),
        content: content
      }
    ]
  end

  defp inferred_tool_results(_role, results, _entry), do: results

  defp normalize_result_status(result) when is_map(result) do
    case result[:status] || result["status"] do
      nil ->
        if result[:is_error] == true or result["is_error"] == true, do: :error, else: nil

      value when is_atom(value) ->
        value

      value when is_binary(value) ->
        value
        |> String.trim()
        |> String.downcase()
        |> case do
          "error" -> :error
          "ok" -> :ok
          "completed" -> :completed
          _ -> nil
        end

      _ ->
        nil
    end
  end

  defp normalize_result_status(_), do: nil

  defp tool_status_from_content(content) when is_binary(content) do
    trimmed = String.trim(content)

    case Jason.decode(trimmed) do
      {:ok, %{"error" => _}} -> :error
      {:ok, %{error: _}} -> :error
      _ -> :completed
    end
  rescue
    _ -> :completed
  end

  defp tool_status_from_content(%{"error" => _}), do: :error
  defp tool_status_from_content(%{error: _}), do: :error
  defp tool_status_from_content(_), do: :completed

  defp normalize_metadata(metadata) when is_map(metadata), do: metadata
  defp normalize_metadata(_), do: %{}

  defp normalize_todos(todos) when is_list(todos) do
    todos
    |> Enum.with_index(1)
    |> Enum.map(fn {todo, idx} ->
      case todo do
        %{} = map ->
          %{
            id: normalize_optional_string(map[:id] || map["id"]) || Integer.to_string(idx),
            content:
              normalize_optional_string(
                map[:content] || map["content"] || map[:text] || map["text"] || map[:title] ||
                  map["title"]
              ) || inspect(map, limit: 40),
            status: normalize_todo_status(map[:status] || map["status"]),
            active_form: normalize_optional_string(map[:active_form] || map["active_form"])
          }

        value when is_binary(value) ->
          %{id: Integer.to_string(idx), content: value, status: :pending, active_form: nil}

        other ->
          %{
            id: Integer.to_string(idx),
            content: inspect(other, limit: 40),
            status: :pending,
            active_form: nil
          }
      end
    end)
  end

  defp normalize_todos(_), do: []

  defp normalize_todo_status(status) when status in [:pending, "pending"], do: :pending

  defp normalize_todo_status(status) when status in [:in_progress, "in_progress"],
    do: :in_progress

  defp normalize_todo_status(status) when status in [:completed, "completed"], do: :completed
  defp normalize_todo_status(status) when status in [:error, "error"], do: :error
  defp normalize_todo_status(_), do: :pending

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_), do: nil
end
