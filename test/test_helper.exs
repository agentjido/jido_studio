Application.put_env(:jido_studio, JidoStudio.TestEndpoint,
  url: [host: "localhost"],
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: String.duplicate("a", 64),
  server: false,
  pubsub_server: JidoStudio.PubSub,
  live_view: [signing_salt: "studio-test"]
)

defmodule JidoStudio.TestBoot do
  @moduledoc false

  def ensure_started(name, starter) do
    case Process.whereis(name) do
      pid when is_pid(pid) ->
        :ok

      _ ->
        case starter.() do
          {:ok, _pid} -> :ok
          {:error, {:already_started, _pid}} -> :ok
        end
    end
  end
end

:ok =
  JidoStudio.TestBoot.ensure_started(JidoStudio.TestEndpoint, fn ->
    JidoStudio.TestEndpoint.start_link()
  end)

ExUnit.start()
