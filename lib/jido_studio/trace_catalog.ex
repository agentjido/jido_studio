defmodule JidoStudio.TraceCatalog do
  @moduledoc false

  @default_events [
    [:jido, :agent, :cmd, :start],
    [:jido, :agent, :cmd, :stop],
    [:jido, :agent, :cmd, :exception],
    [:jido, :agent, :strategy, :init, :start],
    [:jido, :agent, :strategy, :init, :stop],
    [:jido, :agent, :strategy, :init, :exception],
    [:jido, :agent, :strategy, :cmd, :start],
    [:jido, :agent, :strategy, :cmd, :stop],
    [:jido, :agent, :strategy, :cmd, :exception],
    [:jido, :agent, :strategy, :tick, :start],
    [:jido, :agent, :strategy, :tick, :stop],
    [:jido, :agent, :strategy, :tick, :exception],
    [:jido, :agent_server, :signal, :start],
    [:jido, :agent_server, :signal, :stop],
    [:jido, :agent_server, :signal, :exception],
    [:jido, :agent_server, :directive, :start],
    [:jido, :agent_server, :directive, :stop],
    [:jido, :agent_server, :directive, :exception],
    [:jido, :agent_server, :queue, :overflow],
    [:jido, :ai, :react, :start],
    [:jido, :ai, :react, :iteration],
    [:jido, :ai, :react, :complete],
    [:jido, :ai, :tool, :execute, :start],
    [:jido, :ai, :tool, :execute, :stop],
    [:jido, :ai, :tool, :execute, :exception]
  ]

  @spec default_events() :: [[atom()]]
  def default_events, do: @default_events

  @spec configured_events() :: [[atom()]]
  def configured_events do
    Application.get_env(:jido_studio, :trace_events, @default_events)
    |> List.wrap()
    |> Enum.filter(&valid_event_prefix?/1)
    |> Enum.uniq()
  end

  defp valid_event_prefix?(prefix) when is_list(prefix) do
    prefix != [] and Enum.all?(prefix, &is_atom/1)
  end

  defp valid_event_prefix?(_), do: false
end
