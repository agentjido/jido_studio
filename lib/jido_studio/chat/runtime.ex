defmodule JidoStudio.Chat.Runtime do
  @moduledoc false

  @default_timeout_ms 30_000
  @default_stream_poll_ms 120
  @credential_error_tokens [
    "api key",
    "anthropic_api_key",
    "openai_api_key",
    "missing key",
    "unauthorized",
    "authentication",
    "invalid_api_key",
    "forbidden",
    "status 401",
    "status 403"
  ]

  @spec supports?(module() | nil) :: boolean()
  def supports?(agent_module) when is_atom(agent_module) do
    Code.ensure_loaded?(agent_module) and function_exported?(agent_module, :ask_sync, 3)
  rescue
    _ -> false
  end

  def supports?(_), do: false

  @spec supports_async?(module() | nil) :: boolean()
  def supports_async?(agent_module) when is_atom(agent_module) do
    Code.ensure_loaded?(agent_module) and function_exported?(agent_module, :await, 2) and
      (function_exported?(agent_module, :ask, 3) or function_exported?(agent_module, :ask, 2))
  rescue
    _ -> false
  end

  def supports_async?(_), do: false

  @spec ask(module() | nil, pid() | nil, String.t(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def ask(agent_module, pid, message, opts \\ []) when is_binary(message) do
    timeout_ms = normalize_timeout(Keyword.get(opts, :timeout_ms, @default_timeout_ms))

    cond do
      not supports?(agent_module) ->
        {:error, :unsupported}

      not is_pid(pid) ->
        {:error, :instance_unavailable}

      true ->
        do_ask(agent_module, pid, message, timeout_ms)
    end
  end

  @spec start_request(module() | nil, pid() | nil, String.t(), keyword()) ::
          {:ok, term()} | {:error, term()}
  def start_request(agent_module, pid, message, _opts \\ []) when is_binary(message) do
    cond do
      not supports_async?(agent_module) ->
        {:error, :unsupported}

      not is_pid(pid) ->
        {:error, :instance_unavailable}

      true ->
        do_start_request(agent_module, pid, message)
    end
  end

  @spec await_request(module() | nil, term(), keyword()) ::
          {:ok, String.t()} | {:error, term()}
  def await_request(agent_module, request, opts \\ []) do
    timeout_ms = normalize_timeout(Keyword.get(opts, :timeout_ms, @default_timeout_ms))

    cond do
      not supports_async?(agent_module) ->
        {:error, :unsupported}

      is_nil(request) ->
        {:error, :request_unavailable}

      true ->
        do_await_request(agent_module, request, timeout_ms)
    end
  end

  @spec request_id(term()) :: String.t() | nil
  def request_id(%{id: id}) when is_binary(id), do: id
  def request_id(%{"id" => id}) when is_binary(id), do: id
  def request_id(_), do: nil

  @spec streaming_text(pid() | nil) :: {:ok, String.t()} | {:error, term()}
  def streaming_text(pid) when is_pid(pid) do
    case Jido.AgentServer.status(pid) do
      {:ok, status} ->
        details = snapshot_details(status)
        {:ok, normalize_streaming_text(details)}

      {:error, reason} ->
        {:error, normalize_reason(reason)}
    end
  rescue
    error -> {:error, {:exception, error}}
  end

  def streaming_text(_), do: {:error, :instance_unavailable}

  @spec thread_entry_count(pid() | nil) :: {:ok, non_neg_integer()} | {:error, term()}
  def thread_entry_count(pid) when is_pid(pid) do
    case Jido.AgentServer.status(pid) do
      {:ok, status} ->
        {:ok, status |> thread_entries() |> length()}

      {:error, reason} ->
        {:error, normalize_reason(reason)}
    end
  rescue
    error -> {:error, {:exception, error}}
  end

  def thread_entry_count(_), do: {:error, :instance_unavailable}

  @spec stream_snapshot(pid() | nil, keyword()) ::
          {:ok,
           %{
             streaming_text: String.t(),
             tool_events: [map()],
             thread_entry_count: non_neg_integer()
           }}
          | {:error, term()}
  def stream_snapshot(pid, opts \\ [])

  def stream_snapshot(pid, opts) when is_pid(pid) do
    since_entry_count = normalize_since_entry_count(Keyword.get(opts, :since_entry_count, 0))

    case Jido.AgentServer.status(pid) do
      {:ok, status} ->
        entries = thread_entries(status)

        {:ok,
         %{
           streaming_text: normalize_streaming_text(snapshot_details(status)),
           tool_events: extract_tool_events(entries, since_entry_count),
           thread_entry_count: length(entries)
         }}

      {:error, reason} ->
        {:error, normalize_reason(reason)}
    end
  rescue
    error -> {:error, {:exception, error}}
  end

  def stream_snapshot(_pid, _opts), do: {:error, :instance_unavailable}

  @spec stream_poll_ms(keyword()) :: pos_integer()
  def stream_poll_ms(opts \\ []) do
    opts
    |> Keyword.get(:stream_poll_ms, @default_stream_poll_ms)
    |> normalize_stream_poll_ms()
  end

  @spec to_user_message(term(), keyword()) :: String.t()
  def to_user_message(reason, opts \\ []) do
    timeout_ms = normalize_timeout(Keyword.get(opts, :timeout_ms, @default_timeout_ms))

    cond do
      reason == :unsupported ->
        "Chat is not supported for this agent."

      reason == :instance_unavailable ->
        "This instance is no longer running. Start a new instance and try again."

      reason == :request_unavailable ->
        "The request could not be started. Try again."

      timeout_reason?(reason) ->
        "The request timed out after #{timeout_ms}ms. Try again or increase timeout."

      credentials_reason?(reason) ->
        "LLM credentials look missing or invalid. Verify your provider API key configuration."

      true ->
        "The agent request failed. Check Traces for details and try again."
    end
  end

  defp do_ask(agent_module, pid, message, timeout_ms) do
    result =
      try do
        agent_module.ask_sync(pid, message, timeout: timeout_ms)
      rescue
        error -> {:error, {:exception, error}}
      catch
        :exit, reason -> {:error, {:exit, reason}}
      end

    case result do
      {:ok, reply} ->
        {:ok, format_reply(reply)}

      {:error, reason} ->
        {:error, normalize_reason(reason)}

      other ->
        {:error, {:unexpected_reply, other}}
    end
  end

  defp do_start_request(agent_module, pid, message) do
    result =
      try do
        cond do
          function_exported?(agent_module, :ask, 3) ->
            agent_module.ask(pid, message, [])

          function_exported?(agent_module, :ask, 2) ->
            agent_module.ask(pid, message)

          true ->
            {:error, :unsupported}
        end
      rescue
        error -> {:error, {:exception, error}}
      catch
        :exit, reason -> {:error, {:exit, reason}}
      end

    case result do
      {:ok, request} ->
        {:ok, request}

      {:error, reason} ->
        {:error, normalize_reason(reason)}

      other ->
        {:error, {:unexpected_reply, other}}
    end
  end

  defp do_await_request(agent_module, request, timeout_ms) do
    result =
      try do
        agent_module.await(request, timeout: timeout_ms)
      rescue
        error -> {:error, {:exception, error}}
      catch
        :exit, reason -> {:error, {:exit, reason}}
      end

    case result do
      {:ok, reply} ->
        {:ok, format_reply(reply)}

      {:error, reason} ->
        {:error, normalize_reason(reason)}

      other ->
        {:error, {:unexpected_reply, other}}
    end
  end

  defp format_reply(reply) when is_binary(reply) do
    case String.trim(reply) do
      "" -> "(empty response)"
      trimmed -> trimmed
    end
  end

  defp format_reply(reply), do: inspect(reply, pretty: true, limit: 200)

  defp normalize_reason(reason) do
    cond do
      timeout_reason?(reason) -> :timeout
      instance_unavailable_reason?(reason) -> :instance_unavailable
      true -> reason
    end
  end

  defp timeout_reason?(reason), do: token_match?(reason, ["timeout", "timed out"])

  defp instance_unavailable_reason?(reason) do
    reason == :noproc or token_match?(reason, ["noproc", "no process", "process is not alive"])
  end

  defp credentials_reason?(reason), do: token_match?(reason, @credential_error_tokens)

  defp token_match?(reason, tokens) do
    reason
    |> inspect(limit: 400)
    |> String.downcase()
    |> then(fn text -> Enum.any?(tokens, &String.contains?(text, &1)) end)
  end

  defp normalize_timeout(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0,
    do: timeout_ms

  defp normalize_timeout(_), do: @default_timeout_ms

  defp normalize_streaming_text(%{} = details) do
    details
    |> Map.get(:streaming_text, Map.get(details, "streaming_text", ""))
    |> normalize_streaming_text()
  end

  defp normalize_streaming_text(text) when is_binary(text), do: text
  defp normalize_streaming_text(text) when is_list(text), do: to_string(text)
  defp normalize_streaming_text(_), do: ""

  defp normalize_stream_poll_ms(value) when is_integer(value) and value > 0, do: value
  defp normalize_stream_poll_ms(_), do: @default_stream_poll_ms

  defp snapshot_details(status) when is_map(status) do
    status
    |> Map.get(:snapshot, %{})
    |> Map.get(:details, %{})
  end

  defp snapshot_details(_), do: %{}

  defp thread_entries(status) when is_map(status) do
    status
    |> strategy_state()
    |> Map.get(:thread)
    |> case do
      %{entries: entries} when is_list(entries) -> Enum.reverse(entries)
      _ -> []
    end
  end

  defp thread_entries(_), do: []

  defp strategy_state(status) when is_map(status) do
    status
    |> Map.get(:raw_state, %{})
    |> Map.get(:__strategy__, %{})
  end

  defp extract_tool_events(entries, since_entry_count) when is_list(entries) do
    scoped_entries = Enum.drop(entries, min(since_entry_count, length(entries)))

    events =
      scoped_entries
      |> Enum.with_index()
      |> Enum.reduce(%{}, fn {entry, index}, acc ->
        entry
        |> tool_calls_from_entry()
        |> Enum.reduce(acc, fn tool_call, map ->
          Map.put_new(map, tool_call.call_id, %{
            call_id: tool_call.call_id,
            name: tool_call.name,
            arguments: tool_call.arguments,
            result: nil,
            status: :running,
            order: index
          })
        end)
      end)
      |> attach_tool_results(scoped_entries)

    events
    |> Map.values()
    |> Enum.sort_by(& &1.order)
    |> Enum.map(&Map.delete(&1, :order))
  end

  defp extract_tool_events(_entries, _since_entry_count), do: []

  defp attach_tool_results(events, scoped_entries) do
    scoped_entries
    |> Enum.with_index()
    |> Enum.reduce(events, fn {entry, index}, acc ->
      if entry_role(entry) == :tool do
        call_id = to_optional_string(entry_field(entry, :tool_call_id))
        name = to_optional_string(entry_field(entry, :name))
        content = parse_tool_result(entry_field(entry, :content))
        status = if(tool_error_result?(content), do: :error, else: :completed)

        if is_binary(call_id) and call_id != "" do
          Map.update(
            acc,
            call_id,
            %{
              call_id: call_id,
              name: name || "tool",
              arguments: %{},
              result: content,
              status: status,
              order: index
            },
            fn existing ->
              existing
              |> Map.put(:result, content)
              |> Map.put(:status, status)
              |> Map.put(:name, existing.name || name || "tool")
            end
          )
        else
          acc
        end
      else
        acc
      end
    end)
  end

  defp tool_calls_from_entry(entry) do
    case entry_field(entry, :tool_calls) do
      tool_calls when is_list(tool_calls) ->
        tool_calls
        |> Enum.map(&normalize_tool_call/1)
        |> Enum.reject(&is_nil/1)

      _ ->
        []
    end
  end

  defp normalize_tool_call(tool_call) when is_map(tool_call) do
    call_id = to_optional_string(entry_field(tool_call, :id))
    name = to_optional_string(entry_field(tool_call, :name))
    arguments = entry_field(tool_call, :arguments) || %{}

    if is_binary(call_id) and call_id != "" do
      %{call_id: call_id, name: name || "tool", arguments: arguments}
    else
      nil
    end
  end

  defp normalize_tool_call(_), do: nil

  defp parse_tool_result(content) when is_binary(content) do
    trimmed = String.trim(content)

    if trimmed == "" do
      ""
    else
      case Jason.decode(trimmed) do
        {:ok, decoded} -> decoded
        _ -> trimmed
      end
    end
  end

  defp parse_tool_result(content), do: content

  defp tool_error_result?(%{} = result) do
    Map.has_key?(result, :error) or Map.has_key?(result, "error")
  end

  defp tool_error_result?(_), do: false

  defp entry_role(entry) do
    case entry_field(entry, :role) do
      role when role in [:tool, "tool"] -> :tool
      role when role in [:assistant, "assistant"] -> :assistant
      role when role in [:user, "user"] -> :user
      _ -> :unknown
    end
  end

  defp entry_field(map, field) when is_map(map) and is_atom(field) do
    Map.get(map, field, Map.get(map, Atom.to_string(field)))
  end

  defp entry_field(_, _), do: nil

  defp to_optional_string(nil), do: nil
  defp to_optional_string(value) when is_binary(value), do: String.trim(value)
  defp to_optional_string(value), do: value |> to_string() |> String.trim()

  defp normalize_since_entry_count(value) when is_integer(value) and value >= 0, do: value
  defp normalize_since_entry_count(_), do: 0
end
