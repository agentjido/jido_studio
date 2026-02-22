defmodule JidoStudio.LiveOps do
  @moduledoc false

  @default_scope_keys [:project_id, :user_id]

  @spec child_specs(keyword()) :: [Supervisor.child_spec()]
  def child_specs(_opts \\ []) do
    pubsub_specs =
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

    pubsub_specs ++ presence_child_specs()
  end

  @spec enabled?() :: boolean()
  def enabled? do
    config(:enabled, true) != false
  end

  @spec event_stream_limit() :: pos_integer()
  def event_stream_limit do
    case config(:event_stream_limit, 100) do
      value when is_integer(value) and value > 0 -> value
      _ -> 100
    end
  end

  @spec agent_list_poll_ms() :: pos_integer()
  def agent_list_poll_ms do
    case config(:agent_list_poll_ms, 2_000) do
      value when is_integer(value) and value > 0 -> value
      _ -> 2_000
    end
  end

  @spec viewer_tracking?() :: boolean()
  def viewer_tracking? do
    config(:viewer_tracking, true) != false
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

  @spec viewer_topic(String.t()) :: String.t()
  def viewer_topic(instance_id) when is_binary(instance_id) do
    "live_ops:viewers:" <> instance_id
  end

  def viewer_topic(_), do: "live_ops:viewers:unknown"

  @spec subscribe_viewers(String.t()) :: :ok
  def subscribe_viewers(instance_id) when is_binary(instance_id) and instance_id != "" do
    with true <- enabled?(),
         true <- viewer_tracking?(),
         {:ok, pubsub} <- resolve_pubsub() do
      Phoenix.PubSub.subscribe(pubsub, viewer_topic(instance_id))
    else
      _ -> :ok
    end
  end

  def subscribe_viewers(_), do: :ok

  @spec track_viewer(String.t(), String.t(), map()) :: :ok
  def track_viewer(instance_id, viewer_id, metadata \\ %{})

  def track_viewer(instance_id, viewer_id, metadata)
      when is_binary(instance_id) and instance_id != "" and is_binary(viewer_id) and
             viewer_id != "" do
    with true <- enabled?(),
         true <- viewer_tracking?(),
         module when is_atom(module) <- presence_module(),
         true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :track, 4) do
      topic = viewer_topic(instance_id)
      safe_metadata = normalize_viewer_metadata(metadata)
      _ = module.track(self(), topic, viewer_id, safe_metadata)
      :ok
    else
      _ -> :ok
    end
  end

  def track_viewer(_, _, _), do: :ok

  @spec untrack_viewer(String.t(), String.t()) :: :ok
  def untrack_viewer(instance_id, viewer_id)
      when is_binary(instance_id) and instance_id != "" and is_binary(viewer_id) and
             viewer_id != "" do
    with true <- enabled?(),
         true <- viewer_tracking?(),
         module when is_atom(module) <- presence_module(),
         true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :untrack, 3) do
      _ = module.untrack(self(), viewer_topic(instance_id), viewer_id)
      :ok
    else
      _ -> :ok
    end
  end

  def untrack_viewer(_, _), do: :ok

  @spec viewer_count(String.t()) :: non_neg_integer()
  def viewer_count(instance_id) when is_binary(instance_id) and instance_id != "" do
    with true <- enabled?(),
         true <- viewer_tracking?(),
         module when is_atom(module) <- presence_module(),
         true <- Code.ensure_loaded?(module),
         true <- function_exported?(module, :list, 1),
         presences when is_map(presences) <- module.list(viewer_topic(instance_id)) do
      map_size(presences)
    else
      _ -> 0
    end
  rescue
    _ -> 0
  end

  def viewer_count(_), do: 0

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
    case presence_module() do
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

  defp presence_child_specs do
    case presence_module() do
      JidoStudio.Presence ->
        if Process.whereis(JidoStudio.Presence) do
          []
        else
          [{JidoStudio.Presence, pubsub_server: pubsub_name()}]
        end

      _ ->
        []
    end
  end

  defp presence_module do
    case config(:presence_module, :default) do
      false -> nil
      nil -> JidoStudio.Presence
      :default -> JidoStudio.Presence
      module when is_atom(module) -> module
      _ -> JidoStudio.Presence
    end
  end

  defp normalize_viewer_metadata(metadata) when is_map(metadata) do
    metadata
    |> Map.put_new(:connected_at, DateTime.utc_now())
    |> Map.put_new(:node, node())
  end

  defp normalize_viewer_metadata(_), do: %{connected_at: DateTime.utc_now(), node: node()}
end
