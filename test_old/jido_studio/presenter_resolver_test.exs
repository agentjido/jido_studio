defmodule JidoStudio.PresenterResolverTest do
  use ExUnit.Case, async: false

  alias JidoStudio.PresenterResolver
  alias JidoStudio.Presenters

  defmodule FakeStatus do
    defstruct [:snapshot, :raw_state]
  end

  defmodule FakeSnapshot do
    defstruct [:status, :details]
  end

  defmodule AgentNoStrategy do
  end

  defmodule AgentReAct do
    def strategy, do: Jido.AI.Strategies.ReAct
  end

  defmodule AgentBehaviorTree do
    def strategy, do: Jido.Agent.Strategy.BehaviorTree
  end

  defmodule AgentWithOverride do
    def strategy, do: Jido.AI.Strategies.ReAct
    def studio_presenter, do: JidoStudio.Presenters.WeatherAgent
  end

  defmodule AgentWithAskSync do
    def ask_sync(_pid, _message, _opts), do: {:ok, "ok"}
  end

  defmodule BadPresenter do
  end

  setup do
    original = Application.get_env(:jido_studio, :presenter_registry)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:jido_studio, :presenter_registry)
      else
        Application.put_env(:jido_studio, :presenter_registry, original)
      end
    end)

    :ok
  end

  test "falls back to default for unknown strategy" do
    assert PresenterResolver.resolve(AgentNoStrategy) == Presenters.Default
  end

  test "maps known strategies to built-in presenters" do
    assert PresenterResolver.resolve(AgentReAct) == Presenters.ReAct
    assert PresenterResolver.resolve(AgentBehaviorTree) == Presenters.BehaviorTree
  end

  test "agent studio_presenter override takes precedence" do
    Application.put_env(:jido_studio, :presenter_registry, %{
      AgentWithOverride => Presenters.Default,
      Jido.AI.Strategies.ReAct => Presenters.ReAct
    })

    assert PresenterResolver.resolve(AgentWithOverride) == Presenters.WeatherAgent
  end

  test "registry override by agent module wins over strategy mapping" do
    Application.put_env(:jido_studio, :presenter_registry, %{
      AgentReAct => Presenters.WeatherAgent,
      Jido.AI.Strategies.ReAct => Presenters.ReAct
    })

    assert PresenterResolver.resolve(AgentReAct) == Presenters.WeatherAgent
  end

  test "invalid registry presenter falls back to default" do
    Application.put_env(:jido_studio, :presenter_registry, %{AgentNoStrategy => BadPresenter})

    assert PresenterResolver.resolve(AgentNoStrategy) == Presenters.Default
  end

  test "default presenter handles nil runtime status" do
    agent_info = %{module: AgentNoStrategy, status: :available, tags: []}

    model = Presenters.Default.runtime(agent_info, nil, [])

    assert is_list(model.tabs)
    assert is_map(model.sections_by_tab)
    assert is_binary(model.system_prompt)
  end

  test "react presenter handles missing details keys" do
    status = %FakeStatus{snapshot: %FakeSnapshot{status: :running, details: %{}}, raw_state: %{}}
    agent_info = %{module: AgentReAct, status: :running, tags: []}

    model = Presenters.ReAct.runtime(agent_info, status, [])

    assert Enum.any?(model.tabs, &(&1.id == :reasoning))
    assert Enum.any?(model.tabs, &(&1.id == :context))
    assert Map.has_key?(model.sections_by_tab, :reasoning)
    assert Map.has_key?(model.sections_by_tab, :context)
  end

  test "default presenter exposes instance summary and start form schema" do
    summary =
      Presenters.Default.instance_summary(%{}, %{id: "weather-demo-1", pid: self()}, nil, [])

    assert summary.title == "weather-demo"
    assert summary.subtitle == "weather-demo-1"
    assert is_list(summary.badges)

    schema = Presenters.Default.start_form_schema(%{})

    assert Enum.any?(schema, &(&1.name == "instance_id"))
    assert Enum.any?(schema, &(&1.name == "debug"))
    assert Enum.any?(schema, &(&1.name == "initial_state_json"))
  end

  test "react presenter instance summary adds tool call metrics" do
    status = %{
      snapshot: %{
        status: :running,
        details: %{
          queue_length: 0,
          active_requests: [],
          iteration: 1,
          tool_calls: [%{name: "weather"}],
          conversation: [%{role: :user}, %{role: :assistant}]
        }
      },
      raw_state: %{debug: false}
    }

    summary =
      Presenters.ReAct.instance_summary(%{}, %{id: "react-weather-1", pid: self()}, status, [])

    assert {"Tool Calls", "1"} in summary.meta
    assert {"Turns", "2"} in summary.meta
  end

  test "default presenter instance summary honors debug_enabled option" do
    status = %{snapshot: %{status: :idle, details: %{}}, raw_state: %{}}

    summary =
      Presenters.Default.instance_summary(%{}, %{id: "debug-instance", pid: self()}, status,
        debug_enabled: true
      )

    assert Enum.any?(summary.badges, &(&1.label == "Debug On"))
  end

  test "default chat config can be used when presenter does not define chat callback" do
    agent_info = %{module: AgentWithAskSync, status: :available, tags: []}

    config =
      if function_exported?(Presenters.ReAct, :chat_config, 3) do
        apply(Presenters.ReAct, :chat_config, [agent_info, nil, [pid: self(), supported?: true]])
      else
        Presenters.Default.chat_config(agent_info, nil, pid: self(), supported?: true)
      end

    assert config.enabled
    assert config.mode == :ask_sync
    assert config.timeout_ms == 30_000
    assert is_binary(config.placeholder)
  end

  test "weather presenter chat config customizes chat copy" do
    agent_info = %{module: Jido.AI.Examples.WeatherAgent, status: :running, tags: ["example"]}

    config =
      Presenters.WeatherAgent.chat_config(agent_info, nil,
        pid: self(),
        supported?: true
      )

    assert config.enabled
    assert config.placeholder =~ "weather"
    assert config.empty_title == "Weather chat ready"
  end
end
