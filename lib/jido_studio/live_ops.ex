defmodule JidoStudio.LiveOps do
  @moduledoc false

  @default_scope_keys [:project_id, :user_id]

  @spec child_specs(keyword()) :: [Supervisor.child_spec()]
  def child_specs(_opts \\ []) do
    case pubsub_name() do
      JidoStudio.PubSub ->
        if Process.whereis(JidoStudio.PubSub) do
          []
        else
          [{Phoenix.PubSub, name: JidoStudio.PubSub}]
        end

      _ ->
        []
    end
  end

  @spec enabled?() :: boolean()
  def enabled? do
    config(:enabled, true) != false
  end

  @spec auto_follow_default?() :: boolean()
  def auto_follow_default? do
    config(:auto_follow_default, true) == true
  end

  @spec scope_keys() :: [atom()]
  def scope_keys do
    config(:scope_keys, @default_scope_keys)
    |> List.wrap()
    |> Enum.filter(&is_atom/1)
  end

  @spec subscribe_agent_list(keyword() | map()) :: :ok
  def subscribe_agent_list(scope \\ %{}) do
    with true <- enabled?(),
         {:ok, pubsub} <- resolve_pubsub() do
      scope
      |> normalized_scope()
      |> agent_list_topic()
      |> then(&Phoenix.PubSub.subscribe(pubsub, &1))
    else
      _ -> :ok
    end
  end

  @spec subscribe_agent(String.t(), keyword() | map()) :: :ok
  def subscribe_agent(agent_id, scope \\ %{})

  def subscribe_agent(agent_id, scope) when is_binary(agent_id) and agent_id != "" do
    with true <- enabled?(),
         {:ok, pubsub} <- resolve_pubsub() do
      scope
      |> normalized_scope()
      |> agent_topic(agent_id)
      |> then(&Phoenix.PubSub.subscribe(pubsub, &1))
    else
      _ -> :ok
    end
  end

  def subscribe_agent(_, _), do: :ok

  @spec broadcast_agent_list(map(), keyword() | map()) :: :ok
  def broadcast_agent_list(payload, scope \\ %{})

  def broadcast_agent_list(payload, scope) when is_map(payload) do
    with true <- enabled?(),
         {:ok, pubsub} <- resolve_pubsub() do
      message = {:jido_studio_live_ops, :agent_list, payload}

      scope
      |> normalized_scope()
      |> agent_list_topic()
      |> then(&Phoenix.PubSub.broadcast(pubsub, &1, message))

      :ok
    else
      _ -> :ok
    end
  end

  def broadcast_agent_list(_, _), do: :ok

  @spec broadcast_agent(String.t(), map(), keyword() | map()) :: :ok
  def broadcast_agent(agent_id, payload, scope \\ %{})

  def broadcast_agent(agent_id, payload, scope)
      when is_binary(agent_id) and agent_id != "" and is_map(payload) do
    with true <- enabled?(),
         {:ok, pubsub} <- resolve_pubsub() do
      message = {:jido_studio_live_ops, :agent, Map.put(payload, :agent_id, agent_id)}

      scope
      |> normalized_scope()
      |> agent_topic(agent_id)
      |> then(&Phoenix.PubSub.broadcast(pubsub, &1, message))

      :ok
    else
      _ -> :ok
    end
  end

  def broadcast_agent(_, _, _), do: :ok

  @spec presence_available?() :: boolean()
  def presence_available? do
    case config(:presence_module, nil) do
      module when is_atom(module) ->
        Code.ensure_loaded?(module) and function_exported?(module, :list, 1)

      _ ->
        false
    end
  end

  @spec pubsub_name() :: atom()
  def pubsub_name do
    Application.get_env(:jido_studio, :pubsub, JidoStudio.PubSub)
  end

  @spec normalized_scope(keyword() | map()) :: map()
  def normalized_scope(scope) do
    source =
      cond do
        is_map(scope) -> scope
        is_list(scope) -> Map.new(scope)
        true -> %{}
      end

    Enum.reduce(scope_keys(), %{}, fn key, acc ->
      value = Map.get(source, key) || Map.get(source, Atom.to_string(key))

      if is_binary(value) and value != "" do
        Map.put(acc, key, value)
      else
        acc
      end
    end)
  end

  @spec agent_list_topic(map()) :: String.t()
  def agent_list_topic(scope) when is_map(scope) do
    "live_ops:agents:" <> scope_token(scope)
  end

  @spec agent_topic(map(), String.t()) :: String.t()
  def agent_topic(scope, agent_id) when is_binary(agent_id) do
    "live_ops:agent:" <> agent_id <> ":" <> scope_token(scope)
  end

  defp resolve_pubsub do
    pubsub = pubsub_name()

    if is_atom(pubsub) and Process.whereis(pubsub) do
      {:ok, pubsub}
    else
      {:error, :pubsub_unavailable}
    end
  end

  defp scope_token(scope) do
    scope
    |> Enum.sort_by(fn {key, _} -> to_string(key) end)
    |> Enum.map_join("|", fn {key, value} -> "#{key}=#{value}" end)
    |> case do
      "" -> "global"
      value -> value
    end
  end

  defp config(key, default) do
    :jido_studio
    |> Application.get_env(:live_ops, [])
    |> Keyword.get(key, default)
  end
end
