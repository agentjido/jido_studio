defmodule StudioPlayground.DemoAgents do
  @moduledoc false
  use GenServer

  require Logger

  @demo_agents [
    {Jido.AI.Examples.WeatherAgent, "weather-demo"},
    {Jido.AI.Examples.ApiSmokeTestAgent, "api-smoke-demo"},
    {Jido.AI.Examples.TaskListAgent, "tasks-demo"},
    {Jido.AI.Examples.CalculatorAgent, "calculator-demo"},
    {StudioPlayground.DemoAgents.SignalRunnerAgent, "signal-runner-demo"},
    {StudioPlayground.DemoAgents.DeviceControlAgent, "device-control-demo"}
  ]

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, :ok, opts)
  end

  @impl true
  def init(:ok) do
    {:ok, %{}, {:continue, :seed_agents}}
  end

  @impl true
  def handle_continue(:seed_agents, state) do
    _ = Application.ensure_all_started(:jido_ai)

    Enum.each(@demo_agents, &ensure_started/1)

    discovered = JidoStudio.AgentRegistry.list_discovered_agents()
    Logger.info("Studio discovery sees #{length(discovered)} agent modules")

    {:noreply, state}
  end

  defp ensure_started({agent_module, instance_id}) do
    case StudioPlayground.Jido.whereis(instance_id) do
      pid when is_pid(pid) ->
        :ok

      nil ->
        case Jido.start_agent(StudioPlayground.Jido, agent_module, id: instance_id) do
          {:ok, _pid} ->
            Logger.info("Started demo agent #{inspect(agent_module)} as #{instance_id}")

          {:error, {:already_started, _pid}} ->
            :ok

          {:error, reason} ->
            Logger.warning(
              "Failed to start demo agent #{inspect(agent_module)} as #{instance_id}: #{inspect(reason)}"
            )
        end
    end
  rescue
    error ->
      Logger.warning(
        "Failed to start demo agent #{inspect(agent_module)} as #{instance_id}: #{Exception.message(error)}"
      )
  end
end
