defmodule JidoStudio.AgentsRunnerTest do
  use ExUnit.Case, async: false

  @collector_key {__MODULE__, :action_params_test_pid}

  alias JidoStudio.Agents.Runner
  alias JidoStudio.TestJido

  defmodule AtomKeyAction do
    use Jido.Action,
      name: "runner_atom_key_action",
      description: "Test action that expects atom-key payloads",
      schema: [kind: [type: :string, required: true]]

    @impl true
    def run(%{kind: kind} = params, _ctx) do
      if pid = :persistent_term.get({JidoStudio.AgentsRunnerTest, :action_params_test_pid}, nil) do
        send(pid, {:action_params, params})
      end

      {:ok, %{kind: kind, params: params}}
    end
  end

  defmodule StringKeyAction do
    use Jido.Action,
      name: "runner_string_key_action",
      description: "Test action that expects string-key payloads"

    @impl true
    def run(%{"kind" => kind} = params, _ctx) do
      if pid = :persistent_term.get({JidoStudio.AgentsRunnerTest, :action_params_test_pid}, nil) do
        send(pid, {:action_params, params})
      end

      {:ok, %{kind: kind, params: params}}
    end

    def run(params, _ctx), do: {:error, {:unexpected_payload, params}}
  end

  defmodule TypedSignalAgent do
    use Jido.Agent,
      name: "typed_signal_agent",
      description: "Test agent for typed payload routing",
      schema: []

    @impl true
    def signal_routes(_ctx), do: [{"demo.typed", AtomKeyAction}]
  end

  defmodule SchemaLessSignalAgent do
    use Jido.Agent,
      name: "schema_less_signal_agent",
      description: "Test agent for schema-less payload routing",
      schema: []

    @impl true
    def signal_routes(_ctx), do: [{"demo.raw", StringKeyAction}]
  end

  setup do
    :persistent_term.put(@collector_key, self())

    case Process.whereis(TestJido) do
      pid when is_pid(pid) ->
        Process.exit(pid, :kill)
        Process.sleep(20)

      _ ->
        :ok
    end

    start_supervised!(TestJido)

    on_exit(fn ->
      :persistent_term.erase(@collector_key)
    end)

    :ok
  end

  test "keeps atom keys for validated signal payloads" do
    instance_id = "typed-signal-#{System.unique_integer([:positive])}"

    assert {:ok, agent_pid} = Jido.start_agent(TestJido, TypedSignalAgent, id: instance_id)

    assert {:ok, result} =
             Runner.dispatch(
               agent_pid,
               %{
                 kind: :signal,
                 signal_type: "demo.typed",
                 source: :runtime_router,
                 schema: AtomKeyAction.schema()
               },
               %{"kind" => "value"}
             )

    assert result.payload == %{kind: "value"}
    assert_receive {:action_params, %{kind: "value"}}
  end

  test "preserves string keys for schema-less signal payloads" do
    instance_id = "schema-less-signal-#{System.unique_integer([:positive])}"

    assert {:ok, agent_pid} = Jido.start_agent(TestJido, SchemaLessSignalAgent, id: instance_id)

    assert {:ok, result} =
             Runner.dispatch(
               agent_pid,
               %{
                 kind: :signal,
                 signal_type: "demo.raw",
                 source: :runtime_router,
                 schema: nil
               },
               %{"kind" => "value"}
             )

    assert result.payload == %{"kind" => "value"}
    assert_receive {:action_params, %{"kind" => "value"}}
  end
end
