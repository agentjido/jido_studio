defmodule JidoStudio.SignalActions do
  @moduledoc false

  alias Jido.Agent.Route
  alias Jido.AgentServer
  alias Jido.Joi
  alias JidoStudio.TurnTrace

  @compile {:no_warn_undefined, [Jido, AgentServer, Route, Joi]}

  def buttons(actions, %{module: agent_module} = agent) do
    for %{agent: ^agent_module, signal: signal} = action <- actions,
        type = signal.type(),
        {:ok, _route} <- [Route.select(agent, type)],
        schema = Joi.to_json_schema(signal.schema()),
        Map.get(schema, :required, []) == [],
        {:ok, payload} <- [signal.validate_data(%{})] do
      Map.merge(action, %{type: type, schema: schema, payload: payload})
    end
  end

  def dispatch(%{jido: jido, partition: partition}, id, action) do
    with pid when is_pid(pid) <- Jido.whereis_agent(jido, id, partition: partition),
         %{agent: %{module: module} = agent} when module == action.agent <-
           AgentServer.snapshot(pid, 1_500),
         {:ok, _route} <- Route.select(agent, action.type),
         {:ok, signal} <- action.signal.new(%{}) do
      TurnTrace.run(pid, signal, Map.get(action, :reply_fields, []))
    else
      _ -> {:error, :signal_unavailable}
    end
  catch
    :exit, _reason -> {:error, :signal_unavailable}
  end
end
