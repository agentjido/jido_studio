defmodule JidoStudio.SetupTelemetryTest do
  use JidoStudio.ConnCase, async: false

  setup do
    old_jido_instances = Application.get_env(:jido_studio, :jido_instances, :__unset__)

    on_exit(fn ->
      restore_env(:jido_instances, old_jido_instances)
    end)

    :ok
  end

  test "emits runtime and node scope events once per changed selection", %{conn: conn} do
    Application.put_env(:jido_studio, :jido_instances, [
      %{key: "primary", module: JidoStudio.TestJido, label: "Primary"},
      %{key: "secondary", module: JidoStudio.AgentRegistry, label: "Secondary"}
    ])

    attach_telemetry_handler([
      [:jido_studio, :scope, :runtime_selected],
      [:jido_studio, :scope, :node_selected]
    ])

    {:ok, view, _html} = live(conn, "/studio?runtime=primary&node=all")
    flush_telemetry_messages()

    render_patch(view, "/studio?runtime=secondary&node=all")

    assert_receive {:telemetry_event, [:jido_studio, :scope, :runtime_selected], %{count: 1},
                    runtime_meta}

    assert runtime_meta.runtime == "secondary"
    assert runtime_meta.path == "/studio"

    refute_receive {:telemetry_event, [:jido_studio, :scope, :runtime_selected], _, _}, 50

    node_param = URI.encode_www_form(to_string(Node.self()))
    render_patch(view, "/studio?runtime=secondary&node=#{node_param}")

    assert_receive {:telemetry_event, [:jido_studio, :scope, :node_selected], %{count: 1},
                    node_meta}

    assert node_meta.node == to_string(Node.self())
    assert node_meta.runtime == "secondary"
    assert node_meta.path == "/studio"

    refute_receive {:telemetry_event, [:jido_studio, :scope, :node_selected], _, _}, 50

    render_patch(view, "/studio?runtime=secondary&node=#{node_param}")
    refute_receive {:telemetry_event, [:jido_studio, :scope, :node_selected], _, _}, 50
  end

  test "emits setup step_evaluated events for each setup check", %{conn: conn} do
    attach_telemetry_handler([[:jido_studio, :setup, :step_evaluated]])

    {:ok, _view, _html} = live(conn, "/studio")

    events = collect_telemetry_events(5)

    expected_steps =
      MapSet.new([
        "runtime_connected",
        "persistence_selected",
        "realtime_enabled",
        "chat_credentials",
        "smoke_test"
      ])

    received_steps =
      events
      |> Enum.map(fn {_event, _measurements, metadata} -> metadata.step end)
      |> MapSet.new()

    assert received_steps == expected_steps

    assert Enum.all?(events, fn {_event, measurements, metadata} ->
             measurements.count == 1 and
               is_binary(metadata.status) and
               metadata.source == "home"
           end)
  end

  test "emits setup profile_selected event when profile is chosen", %{conn: conn} do
    attach_telemetry_handler([[:jido_studio, :setup, :profile_selected]])

    {:ok, view, _html} = live(conn, "/studio")

    view
    |> element(
      "button[phx-click='select_setup_profile'][phx-value-value='team_durable_ops']",
      "Team Durable Ops"
    )
    |> render_click()

    assert_receive {:telemetry_event, [:jido_studio, :setup, :profile_selected], %{count: 1},
                    metadata}

    assert metadata.profile == "team_durable_ops"
    assert metadata.source == "home"
    assert metadata.node == "all"
  end

  test "emits setup profile_selected from settings source", %{conn: conn} do
    attach_telemetry_handler([[:jido_studio, :setup, :profile_selected]])

    {:ok, view, _html} = live(conn, "/studio/settings")

    view
    |> element(
      "button[phx-click='select_setup_profile'][phx-value-value='chat_demo']",
      "Chat Demo Showcase"
    )
    |> render_click()

    assert_receive {:telemetry_event, [:jido_studio, :setup, :profile_selected], %{count: 1},
                    metadata}

    assert metadata.profile == "chat_demo"
    assert metadata.source == "settings"
    assert metadata.node == "all"
  end

  defp attach_telemetry_handler(events) do
    handler_id = "jido-studio-setup-telemetry-#{System.unique_integer([:positive])}"

    :ok =
      :telemetry.attach_many(
        handler_id,
        events,
        &__MODULE__.handle_telemetry_event/4,
        self()
      )

    on_exit(fn ->
      :telemetry.detach(handler_id)
    end)

    :ok
  end

  defp collect_telemetry_events(expected_count), do: collect_telemetry_events(expected_count, [])

  defp collect_telemetry_events(0, acc), do: Enum.reverse(acc)

  defp collect_telemetry_events(expected_count, acc) when expected_count > 0 do
    receive do
      {:telemetry_event, event, measurements, metadata} ->
        collect_telemetry_events(expected_count - 1, [{event, measurements, metadata} | acc])
    after
      1_000 ->
        flunk("expected #{expected_count} additional telemetry events")
    end
  end

  defp flush_telemetry_messages do
    receive do
      {:telemetry_event, _event, _measurements, _metadata} ->
        flush_telemetry_messages()
    after
      0 ->
        :ok
    end
  end

  defp restore_env(key, :__unset__), do: Application.delete_env(:jido_studio, key)
  defp restore_env(key, value), do: Application.put_env(:jido_studio, key, value)

  def handle_telemetry_event(event, measurements, metadata, pid) do
    send(pid, {:telemetry_event, event, measurements, metadata})
  end
end
