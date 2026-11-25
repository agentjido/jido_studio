defmodule JidoStudio.Beginner do
  @moduledoc false

  @spec enabled?() :: boolean()
  def enabled? do
    :jido_studio
    |> Application.get_env(:beginner_agent, [])
    |> Keyword.get(:enabled, true)
    |> Kernel.!=(false)
  end

  @spec module() :: module()
  def module, do: JidoStudio.BeginnerAgent
end
