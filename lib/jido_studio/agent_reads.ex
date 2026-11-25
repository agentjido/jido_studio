defmodule JidoStudio.AgentReads do
  @moduledoc false

  alias Jido.AgentServer
  alias Jido.AgentServer.{Snapshot, Status}
  alias JidoStudio.{SignalActions, TurnHistory}

  # Shell-only hosts can omit the optional Jido dependency.
  @compile {:no_warn_undefined, [Jido, AgentServer]}
  @timeout 1_500

  def list(%{jido: jido, partition: partition} = runtime) do
    with :ok <- available(runtime) do
      case Jido.list_agents(jido, partition: partition) do
        agents when is_list(agents) -> {:ok, agents |> Enum.map(&elem(&1, 0)) |> Enum.sort()}
        {:error, _reason} -> {:error, :runtime_unavailable}
      end
    end
  end

  def status(runtime, id) do
    with {:ok, pid} <- find_agent(runtime, id),
         {:ok, %{__struct__: Status} = status} <-
           read(fn -> AgentServer.status(pid, @timeout) end) do
      {:ok,
       %{
         namespace: status.agent_address.namespace,
         activation_id: status.agent_activation_id,
         work_state: status.work_state,
         residency: status.residency,
         ready?: status.ready?,
         durability: status.durability,
         queue_depth: status.queue_depth,
         active_turn_id: status.active_turn_id
       }}
    end
  end

  def turns(runtime, id) do
    with {:ok, pid} <- find_agent(runtime, id) do
      read(fn -> TurnHistory.list(pid, @timeout) end)
    end
  end

  def snapshot(runtime, id, actions) do
    with {:ok, pid} <- find_agent(runtime, id),
         {:ok, %{__struct__: Snapshot} = snapshot} <-
           read(fn -> AgentServer.snapshot(pid, @timeout) end) do
      agent = snapshot.agent

      {:ok,
       %{
         name: agent.name,
         description: agent.description,
         module: agent.module,
         version: agent.vsn,
         activation_id: snapshot.agent_activation_id,
         revision: snapshot.agent_revision,
         persistence_revision: snapshot.persistence_revision,
         field_count: map_size(agent.state),
         signal_buttons: SignalActions.buttons(actions, agent)
       }}
    end
  end

  defp find_agent(%{jido: jido, partition: partition} = runtime, id) do
    with :ok <- available(runtime) do
      case Jido.whereis_agent(jido, id, partition: partition) do
        pid when is_pid(pid) -> {:ok, pid}
        nil -> {:error, :not_found}
        {:error, _reason} -> {:error, :runtime_unavailable}
      end
    end
  end

  defp available(%{jido: nil}), do: {:error, :not_configured}

  defp available(%{jido: jido}) do
    if Code.ensure_loaded?(Jido) and Process.whereis(jido),
      do: :ok,
      else: {:error, :runtime_unavailable}
  end

  defp read(fun) do
    case fun.() do
      {:error, :not_ready} -> {:error, :not_ready}
      {:error, _reason} -> {:error, :read_failed}
      result -> {:ok, result}
    end
  catch
    :exit, {:timeout, _details} -> {:error, :timeout}
    :exit, _reason -> {:error, :read_failed}
  end
end
