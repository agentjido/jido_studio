defmodule JidoStudio.Live.AgentsLive.Support.ScopeHelpers do
  @moduledoc false

  alias JidoStudio.TraceBuffer

  def normalize_scope_filters(scope_params) when is_map(scope_params) do
    %{
      project_id: normalize_scope_value(scope_params["project_id"] || scope_params[:project_id]),
      user_id: normalize_scope_value(scope_params["user_id"] || scope_params[:user_id]),
      agent_id: normalize_scope_value(scope_params["agent_id"] || scope_params[:agent_id])
    }
  end

  def normalize_scope_filters(_), do: %{project_id: nil, user_id: nil, agent_id: nil}

  def merge_scope_filters(existing, nil) when is_map(existing), do: existing

  def merge_scope_filters(existing, scope_params) when is_map(existing) do
    incoming = normalize_scope_filters(scope_params)

    if incoming.project_id || incoming.user_id || incoming.agent_id do
      incoming
    else
      existing
    end
  end

  def merge_scope_filters(_, scope_params), do: normalize_scope_filters(scope_params)

  def normalize_scope_value(nil), do: nil

  def normalize_scope_value(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  def normalize_scope_value(value) when is_atom(value), do: Atom.to_string(value)
  def normalize_scope_value(_), do: nil

  def filter_agents_by_scope(agents, nil), do: agents

  def filter_agents_by_scope(agents, scope_filters)
      when is_list(agents) and is_map(scope_filters) do
    agent_id_query = normalize_scope_value(scope_filters.agent_id)
    scoped_instance_ids = scope_candidate_instance_ids(scope_filters)

    Enum.filter(agents, fn agent ->
      running_instances = agent.running_instances || []
      instance_ids = Enum.map(running_instances, &to_string(&1.id))

      agent_match? =
        case agent_id_query do
          nil ->
            true

          query ->
            String.contains?(String.downcase(agent.slug || ""), String.downcase(query)) or
              String.contains?(String.downcase(agent.name || ""), String.downcase(query)) or
              Enum.any?(
                instance_ids,
                &String.contains?(String.downcase(&1), String.downcase(query))
              )
        end

      scope_match? =
        case scoped_instance_ids do
          :all ->
            true

          ids when is_struct(ids, MapSet) ->
            if MapSet.size(ids) > 0 do
              Enum.any?(instance_ids, &MapSet.member?(ids, &1))
            else
              false
            end

          _ ->
            true
        end

      agent_match? and scope_match?
    end)
  end

  def filter_agents_by_scope(agents, _), do: agents

  def scope_candidate_instance_ids(scope_filters) do
    project_id = normalize_scope_value(scope_filters.project_id)
    user_id = normalize_scope_value(scope_filters.user_id)

    if is_nil(project_id) and is_nil(user_id) do
      :all
    else
      TraceBuffer.events(2_000)
      |> Enum.reduce(MapSet.new(), fn event, acc ->
        scope = event[:scope] || event[:metadata] || %{}
        event_project_id = scope[:project_id] || scope["project_id"]
        event_user_id = scope[:user_id] || scope["user_id"]
        agent_id = event[:agent_id] || event[:instance_id]

        project_ok = is_nil(project_id) or to_string(event_project_id) == project_id
        user_ok = is_nil(user_id) or to_string(event_user_id) == user_id

        if project_ok and user_ok and is_binary(agent_id) do
          MapSet.put(acc, agent_id)
        else
          acc
        end
      end)
    end
  end

  def scope_filters_match?(_event_scope, nil), do: true

  def scope_filters_match?(event_scope, scope_filters) when is_map(scope_filters) do
    scope =
      cond do
        is_map(event_scope) -> event_scope
        is_list(event_scope) -> Map.new(event_scope)
        true -> %{}
      end

    project_id = normalize_scope_value(scope_filters.project_id)
    user_id = normalize_scope_value(scope_filters.user_id)

    project_ok =
      is_nil(project_id) or to_string(scope[:project_id] || scope["project_id"]) == project_id

    user_ok = is_nil(user_id) or to_string(scope[:user_id] || scope["user_id"]) == user_id
    project_ok and user_ok
  end

  def scope_filters_match?(_, _), do: true
end
