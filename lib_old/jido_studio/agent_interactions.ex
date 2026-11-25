defmodule JidoStudio.AgentInteractions do
  @moduledoc false

  @default_internal_tags ["internal"]

  @spec enabled?() :: boolean()
  def enabled? do
    config(:enabled, true) != false
  end

  @spec default_tab() :: :auto | :chat | :interact
  def default_tab do
    case config(:default_tab, :auto) do
      value when value in [:auto, :chat, :interact] ->
        value

      value when is_binary(value) ->
        value
        |> String.trim()
        |> String.downcase()
        |> case do
          "chat" -> :chat
          "interact" -> :interact
          _ -> :auto
        end

      _ ->
        :auto
    end
  end

  @spec runner_timeout_ms() :: pos_integer()
  def runner_timeout_ms do
    case config(:runner_timeout_ms, 5_000) do
      value when is_integer(value) and value > 0 -> value
      _ -> 5_000
    end
  end

  @spec runner_history_limit() :: pos_integer()
  def runner_history_limit do
    case config(:runner_history_limit, 20) do
      value when is_integer(value) and value > 0 -> value
      _ -> 20
    end
  end

  @spec internal_agent_tags() :: [String.t()]
  def internal_agent_tags do
    config(:internal_agent_tags, @default_internal_tags)
    |> List.wrap()
    |> Enum.map(fn
      value when is_binary(value) -> value
      value when is_atom(value) -> Atom.to_string(value)
      value -> to_string(value)
    end)
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
    |> Enum.map(&String.downcase/1)
    |> Enum.uniq()
  end

  defp config(key, default) do
    :jido_studio
    |> Application.get_env(:agent_interactions, [])
    |> Keyword.get(key, default)
  end
end
