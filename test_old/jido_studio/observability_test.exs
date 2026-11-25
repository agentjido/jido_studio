defmodule JidoStudio.ObservabilityTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Observability
  alias JidoStudio.TraceBuffer

  setup do
    ensure_started(JidoStudio.TraceBuffer, fn -> JidoStudio.TraceBuffer.start_link([]) end)

    table = :jido_studio_traces

    if :ets.whereis(table) != :undefined do
      :ets.delete_all_objects(table)
    end

    :ok
  end

  defp ensure_started(name, starter) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case starter.() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end
    end
  end

  test "trace_preview/3 returns normalized preview payload" do
    preview = Observability.trace_preview("instance-1", nil, limit: 5, include_agent_debug?: true)

    assert is_map(preview)
    assert preview.events == []
    assert preview.telemetry_events == []
    assert preview.debug_events == []
    assert preview.debug_error == nil
  end

  test "query_events/2 supports telemetry source filtering" do
    send(
      TraceBuffer,
      {:telemetry_event, [:jido, :ai, :react, :iteration], %{system_time: System.system_time()},
       %{agent_id: "instance-1", trace_id: "trace-1"}}
    )

    Process.sleep(20)

    events = Observability.query_events(nil, filters: %{source: :telemetry}, limit: 20)

    assert events != []
    assert Enum.all?(events, &(&1.source == :telemetry))
  end
end
