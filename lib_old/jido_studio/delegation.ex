defmodule JidoStudio.Delegation do
  @moduledoc false

  alias JidoStudio.Persistence
  alias JidoStudio.Tracing

  @subagents_namespace "subagents"
  @tasks_namespace "tasks"
  @tool_runs_namespace "tool_runs"
  @middleware_namespace "middleware_snapshots"

  @spec enabled?() :: boolean()
  def enabled? do
    :jido_studio
    |> Application.get_env(:delegation, [])
    |> Keyword.get(:enabled, true) != false
  end

  @spec list_subagents(String.t(), keyword()) :: [map()]
  def list_subagents(parent_agent_id, opts \\ [])

  def list_subagents(parent_agent_id, opts) when is_binary(parent_agent_id) do
    limit = normalize_limit(Keyword.get(opts, :limit, 200), 200)
    scope = normalize_scope(Keyword.get(opts, :scope))

    Persistence.list_docs(@subagents_namespace, order: :desc, limit: limit, sort_by: :updated_at)
    |> Enum.filter(fn doc ->
      doc_parent = doc[:parent_agent_id] || doc["parent_agent_id"]
      doc_parent == parent_agent_id and scope_match?(doc, scope)
    end)
    |> Enum.sort_by(&Map.get(&1, :updated_at, 0), :desc)
  end

  def list_subagents(_, _), do: []

  @spec get_subagent(String.t(), String.t(), keyword()) :: map() | nil
  def get_subagent(parent_agent_id, subagent_id, opts \\ [])

  def get_subagent(parent_agent_id, subagent_id, opts)
      when is_binary(parent_agent_id) and is_binary(subagent_id) do
    list_subagents(parent_agent_id, opts)
    |> Enum.find(fn sub ->
      sub[:agent_id] == subagent_id
    end)
  end

  def get_subagent(_, _, _), do: nil

  @spec delegation_graph(String.t(), keyword()) :: map()
  def delegation_graph(trace_id, opts \\ [])

  def delegation_graph(trace_id, opts) when is_binary(trace_id) do
    limit = normalize_limit(Keyword.get(opts, :limit, 2_000), 2_000)

    events = Tracing.list_trace_events(trace_id, order: :asc, limit: limit)

    event_edges =
      Enum.reduce(events, MapSet.new(), fn event, acc ->
        parent = event[:parent_agent_id]
        child = event[:agent_id]

        if is_binary(parent) and is_binary(child) and parent != child do
          MapSet.put(acc, {parent, child, :trace})
        else
          acc
        end
      end)

    doc_edges =
      Persistence.list_docs(@subagents_namespace,
        order: :desc,
        limit: 1_000,
        sort_by: :updated_at
      )
      |> Enum.reduce(MapSet.new(), fn doc, acc ->
        if doc[:trace_id] == trace_id and is_binary(doc[:parent_agent_id]) and
             is_binary(doc[:agent_id]) do
          MapSet.put(acc, {doc[:parent_agent_id], doc[:agent_id], :doc})
        else
          acc
        end
      end)

    edges =
      event_edges
      |> MapSet.union(doc_edges)
      |> Enum.map(fn {parent, child, source} ->
        %{from: parent, to: child, source: source}
      end)

    nodes =
      edges
      |> Enum.flat_map(fn edge -> [edge.from, edge.to] end)
      |> Enum.uniq()
      |> Enum.map(&%{id: &1})

    %{trace_id: trace_id, nodes: nodes, edges: edges}
  end

  def delegation_graph(_, _), do: %{trace_id: nil, nodes: [], edges: []}

  @spec list_tasks(String.t(), keyword()) :: [map()]
  def list_tasks(agent_id, opts \\ [])

  def list_tasks(agent_id, opts) when is_binary(agent_id) do
    limit = normalize_limit(Keyword.get(opts, :limit, 300), 300)
    scope = normalize_scope(Keyword.get(opts, :scope))

    Persistence.list_docs(@tasks_namespace, order: :desc, limit: limit, sort_by: :updated_at)
    |> Enum.filter(fn task ->
      (task[:agent_id] == agent_id or task[:parent_agent_id] == agent_id) and
        scope_match?(task, scope)
    end)
    |> Enum.sort_by(&task_sort_key/1, :desc)
  end

  def list_tasks(_, _), do: []

  @spec list_subagent_events(String.t(), String.t(), keyword()) :: [map()]
  def list_subagent_events(trace_id, subagent_id, opts \\ [])

  def list_subagent_events(trace_id, subagent_id, opts)
      when is_binary(trace_id) and is_binary(subagent_id) do
    limit = normalize_limit(Keyword.get(opts, :limit, 400), 400)

    Tracing.list_trace_events(trace_id, order: :asc, limit: limit)
    |> Enum.filter(fn event ->
      event_agent_id = event[:agent_id]
      parent_agent_id = event[:parent_agent_id]
      metadata = event[:metadata] || %{}
      metadata_subagent_id = metadata[:subagent_id] || metadata["subagent_id"]

      event_agent_id == subagent_id or parent_agent_id == subagent_id or
        metadata_subagent_id == subagent_id
    end)
  end

  def list_subagent_events(_, _, _), do: []

  @spec list_tool_runs(String.t(), keyword()) :: [map()]
  def list_tool_runs(agent_id, opts \\ [])

  def list_tool_runs(agent_id, opts) when is_binary(agent_id) do
    limit = normalize_limit(Keyword.get(opts, :limit, 100), 100)

    Persistence.list_docs(@tool_runs_namespace, order: :desc, limit: limit, sort_by: :updated_at)
    |> Enum.filter(fn run ->
      run[:agent_id] == agent_id
    end)
    |> Enum.sort_by(&Map.get(&1, :updated_at, 0), :desc)
  end

  def list_tool_runs(_, _), do: []

  @spec list_middleware_snapshots(String.t(), keyword()) :: [map()]
  def list_middleware_snapshots(agent_id, opts \\ [])

  def list_middleware_snapshots(agent_id, opts) when is_binary(agent_id) do
    limit = normalize_limit(Keyword.get(opts, :limit, 50), 50)

    Persistence.list_docs(@middleware_namespace, order: :desc, limit: limit, sort_by: :updated_at)
    |> Enum.filter(fn item ->
      item[:agent_id] == agent_id
    end)
    |> Enum.sort_by(&Map.get(&1, :updated_at, 0), :desc)
  end

  def list_middleware_snapshots(_, _), do: []

  defp task_sort_key(task) do
    task[:updated_at] || task[:last_event_at] || task[:started_at] || 0
  end

  defp normalize_scope(nil), do: nil
  defp normalize_scope(scope) when is_map(scope), do: scope
  defp normalize_scope(scope) when is_list(scope), do: Map.new(scope)
  defp normalize_scope(_), do: nil

  defp scope_match?(_doc, nil), do: true

  defp scope_match?(doc, scope) when is_map(doc) and is_map(scope) do
    doc_scope = doc[:scope] || %{}

    Enum.all?(scope, fn {key, expected} ->
      doc_scope[key] == expected or doc_scope[to_string(key)] == expected
    end)
  end

  defp scope_match?(_, _), do: true

  defp normalize_limit(value, _default) when is_integer(value) and value > 0, do: value
  defp normalize_limit(_value, default), do: default
end
