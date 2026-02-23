defmodule JidoStudio.BeginnerAgent.Actions.Ping do
  @moduledoc false

  use Jido.Action,
    name: "beginner_ping",
    description: "Record a deterministic ping message.",
    schema: [
      message: [type: :string, default: "pong"],
      count: [type: :non_neg_integer, default: 1]
    ]

  @impl true
  def run(params, _ctx) do
    message = Map.get(params, :message, "pong")
    count = Map.get(params, :count, 1)

    {:ok,
     %{
       ping_count: count,
       last_message: "Ping acknowledged: #{message}"
     }}
  end
end
