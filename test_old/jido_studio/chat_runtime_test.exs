defmodule JidoStudio.ChatRuntimeTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Chat.Runtime

  defmodule SupportedAgent do
    def ask_sync(_pid, "ok", _opts), do: {:ok, "Sunny and mild"}
    def ask_sync(_pid, "timeout", _opts), do: {:error, :timeout}
    def ask_sync(_pid, _message, _opts), do: {:error, :provider_down}
  end

  defmodule AsyncSupportedAgent do
    def ask(_pid, "ok", _opts), do: {:ok, %{id: "req-1", query: "ok"}}
    def ask(_pid, _message, _opts), do: {:error, :bad_request}

    def await(%{id: "req-1"}, _opts), do: {:ok, "Streaming complete"}
    def await(_request, _opts), do: {:error, :timeout}
  end

  test "ask returns a successful assistant response" do
    assert {:ok, "Sunny and mild"} = Runtime.ask(SupportedAgent, self(), "ok")
  end

  test "ask returns unsupported when module does not expose ask_sync/3" do
    assert {:error, :unsupported} = Runtime.ask(__MODULE__, self(), "hello")
  end

  test "timeout error is normalized and exposed with timeout details" do
    assert {:error, :timeout} = Runtime.ask(SupportedAgent, self(), "timeout", timeout_ms: 12_345)

    message = Runtime.to_user_message(:timeout, timeout_ms: 12_345)
    assert message =~ "12345ms"
    assert message =~ "timed out"
  end

  test "generic provider errors map to a safe fallback message" do
    assert {:error, :provider_down} = Runtime.ask(SupportedAgent, self(), "boom")

    message = Runtime.to_user_message(:provider_down)
    assert message =~ "Check Traces"
  end

  test "credential-shaped errors map to credentials guidance" do
    message = Runtime.to_user_message({:http_error, 401, "ANTHROPIC_API_KEY missing"})
    assert message =~ "credentials"
  end

  test "supports_async?/1 detects ask/3 + await/2 style agents" do
    assert Runtime.supports_async?(AsyncSupportedAgent)
    refute Runtime.supports_async?(SupportedAgent)
  end

  test "start_request and await_request support async chat lifecycle" do
    assert {:ok, request} = Runtime.start_request(AsyncSupportedAgent, self(), "ok")
    assert Runtime.request_id(request) == "req-1"
    assert {:ok, "Streaming complete"} = Runtime.await_request(AsyncSupportedAgent, request)
  end

  test "streaming helpers expose sane defaults" do
    assert Runtime.stream_poll_ms(stream_poll_ms: 42) == 42
    assert Runtime.stream_poll_ms(stream_poll_ms: 0) == 120
    assert Runtime.to_user_message(:request_unavailable) =~ "could not be started"
  end

  test "stream snapshot helpers return instance unavailable when pid is invalid" do
    assert {:error, :instance_unavailable} = Runtime.stream_snapshot(nil)
    assert {:error, :instance_unavailable} = Runtime.thread_entry_count(nil)
  end
end
