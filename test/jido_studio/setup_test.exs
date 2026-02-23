defmodule JidoStudio.SetupTest do
  use ExUnit.Case, async: false

  alias JidoStudio.Setup
  alias JidoStudio.TestJido

  setup do
    old_thread_persistence = Application.get_env(:jido_studio, :thread_persistence, :__unset__)
    old_thread_storage = Application.get_env(:jido_studio, :thread_storage, :__unset__)
    old_live_ops = Application.get_env(:jido_studio, :live_ops, :__unset__)

    on_exit(fn ->
      restore_env(:thread_persistence, old_thread_persistence)
      restore_env(:thread_storage, old_thread_storage)
      restore_env(:live_ops, old_live_ops)
    end)

    :ok
  end

  test "runtime check passes when runtime is reachable" do
    ensure_runtime_started()

    setup =
      Setup.build(
        scope: {:node, Node.self()},
        jido_instance: TestJido,
        prefix: "/studio",
        runtime_key: nil,
        node_param: "all",
        agents: []
      )

    runtime_check = check_by_id(setup.checks, :runtime_connected)
    assert runtime_check.status == :pass
  end

  test "runtime check fails when runtime is missing" do
    setup =
      Setup.build(
        scope: {:node, Node.self()},
        jido_instance: nil,
        prefix: "/studio",
        runtime_key: nil,
        node_param: "all",
        agents: []
      )

    runtime_check = check_by_id(setup.checks, :runtime_connected)

    assert runtime_check.status == :fail
    assert setup.core_ready? == false
  end

  test "runtime check classifies timeout and nodedown failures" do
    timeout_setup =
      Setup.build(
        scope: {:node, Node.self()},
        jido_instance: TestJido,
        prefix: "/studio",
        runtime_key: nil,
        node_param: "all",
        agents: [],
        rpc_fun: fn _scope, _module, _fun, _args ->
          {:error, %{kind: :timeout, reason: :timeout}}
        end
      )

    timeout_check = check_by_id(timeout_setup.checks, :runtime_connected)

    assert timeout_check.status == :fail
    assert timeout_check.detail =~ "timeout"

    nodedown_setup =
      Setup.build(
        scope: {:node, Node.self()},
        jido_instance: TestJido,
        prefix: "/studio",
        runtime_key: nil,
        node_param: "all",
        agents: [],
        rpc_fun: fn _scope, _module, _fun, _args ->
          {:error, %{kind: :nodedown, reason: :nodedown}}
        end
      )

    nodedown_check = check_by_id(nodedown_setup.checks, :runtime_connected)

    assert nodedown_check.status == :fail
    assert nodedown_check.detail =~ "node down"
  end

  test "runtime check warns when some nodes are reachable and some are unavailable" do
    setup =
      Setup.build(
        scope: :all,
        jido_instance: TestJido,
        prefix: "/studio",
        runtime_key: nil,
        node_param: "all",
        agents: [],
        rpc_fun: fn _scope, _module, _fun, _args ->
          {:ok,
           [
             %{node: Node.self(), ok?: true, value: 2, error: nil},
             %{node: :missing@node, ok?: false, value: nil, error: %{kind: :nodedown}}
           ]}
        end
      )

    runtime_check = check_by_id(setup.checks, :runtime_connected)

    assert runtime_check.status == :warn
    assert runtime_check.detail =~ "unavailable"
  end

  test "persistence check warns in ETS mode and passes in durable mode" do
    Application.put_env(:jido_studio, :thread_persistence, true)

    Application.put_env(
      :jido_studio,
      :thread_storage,
      {Jido.Storage.ETS, table: :setup_test_threads}
    )

    ets_setup =
      Setup.build(
        scope: :all,
        jido_instance: TestJido,
        prefix: "/studio",
        runtime_key: nil,
        node_param: "all",
        agents: []
      )

    ets_check = check_by_id(ets_setup.checks, :persistence_selected)
    assert ets_check.status == :warn
    assert ets_check.durable? == false

    Application.put_env(
      :jido_studio,
      :thread_storage,
      {Jido.Storage.File, path: "tmp/setup_test_storage"}
    )

    durable_setup =
      Setup.build(
        scope: :all,
        jido_instance: TestJido,
        prefix: "/studio",
        runtime_key: nil,
        node_param: "all",
        agents: []
      )

    durable_check = check_by_id(durable_setup.checks, :persistence_selected)
    assert durable_check.status == :pass
    assert durable_check.durable? == true
  end

  test "realtime check reflects disabled live ops and optional chat is info when keys missing" do
    Application.put_env(:jido_studio, :live_ops, enabled: false, presence_module: false)

    setup =
      Setup.build(
        scope: :all,
        jido_instance: TestJido,
        prefix: "/studio",
        runtime_key: nil,
        node_param: "all",
        agents: []
      )

    realtime_check = check_by_id(setup.checks, :realtime_enabled)
    chat_check = check_by_id(setup.checks, :chat_credentials)

    assert realtime_check.status == :warn
    assert chat_check.status == :info
  end

  test "smoke check passes when a running instance is present" do
    ensure_runtime_started()

    setup =
      Setup.build(
        scope: :all,
        jido_instance: TestJido,
        prefix: "/studio",
        runtime_key: nil,
        node_param: "all",
        agents: [
          %{
            slug: "calculator-agent",
            running_instances: [%{id: "instance-1"}]
          }
        ]
      )

    smoke_check = check_by_id(setup.checks, :smoke_test)

    assert smoke_check.status == :pass
    assert setup.core_ready? == true
  end

  defp check_by_id(checks, id) do
    Enum.find(checks, &(&1.id == id)) ||
      raise "missing check #{inspect(id)}"
  end

  defp ensure_runtime_started do
    case Process.whereis(TestJido) do
      pid when is_pid(pid) ->
        :ok

      _ ->
        start_supervised!({TestJido, []})
    end
  end

  defp restore_env(key, :__unset__), do: Application.delete_env(:jido_studio, key)
  defp restore_env(key, value), do: Application.put_env(:jido_studio, key, value)
end
