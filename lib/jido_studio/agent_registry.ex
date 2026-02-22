defmodule JidoStudio.AgentRegistry do
  @moduledoc """
  Agent discovery for Jido Studio.

  Combines static module discovery (via `Jido.Discovery`) with runtime
  process listing (via a configured Jido instance) to provide a unified
  view of all agents in the system.
  """

  alias JidoStudio.Cluster.RPC
  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Naming

  @type agent_info :: %{
          module: module(),
          name: String.t(),
          description: String.t(),
          slug: String.t() | nil,
          category: atom() | String.t() | nil,
          tags: [atom() | String.t()],
          status: :available | :running | :offline,
          running_instances: [instance_info()],
          pid: pid() | nil,
          id: String.t() | nil
        }

  @type instance_info :: %{
          optional(:node) => node(),
          id: String.t(),
          pid: pid()
        }

  @doc """
  Returns the configured Jido instance module.

  Resolution order:
  1. Explicit value passed in opts
  2. Application env `config :jido_studio, :jido_instance`
  3. `nil` (static discovery only)
  """
  @spec jido_instance(keyword()) :: module() | nil
  def jido_instance(opts \\ []) do
    Keyword.get_lazy(opts, :jido_instance, fn ->
      Application.get_env(:jido_studio, :jido_instance)
    end)
  end

  @doc """
  Lists all known agents, merging static discovery with runtime state.

  Returns a list of agent info maps suitable for display in the UI.

  ## Options

  - `:jido_instance` - Override the configured Jido instance module
  - `:scope` - `:all` (default) or `{:node, node}`
  """
  @spec list_agents(keyword()) :: [agent_info()]
  def list_agents(opts \\ []) do
    scope = Keyword.get(opts, :scope, Scope.default_scope()) |> Scope.normalize_scope()
    local_opts = Keyword.delete(opts, :scope)

    case scope do
      :all ->
        list_agents_all_nodes(local_opts)

      {:node, node} ->
        if node == Node.self() do
          list_agents_local(local_opts)
        else
          case RPC.call({:node, node}, __MODULE__, :list_agents_local, [local_opts]) do
            {:ok, agents} when is_list(agents) -> annotate_node(agents, node)
            _ -> []
          end
        end
    end
  end

  @doc false
  @spec list_agents_local(keyword()) :: [agent_info()]
  def list_agents_local(opts \\ []) do
    discovered = list_discovered_agents_local()
    instance = jido_instance(opts)
    running = list_running_agents(instance)

    merge_agents(discovered, running)
  end

  @doc """
  Looks up a single agent by its discovery slug.

  Returns an agent info map or `nil` if not found.
  """
  @spec get_agent(String.t(), keyword()) :: agent_info() | nil
  def get_agent(slug, opts \\ []) do
    list_agents(opts)
    |> Enum.find(&(&1.slug == slug))
  end

  @doc """
  Returns running instances for an agent slug.
  """
  @spec get_instances(String.t(), keyword()) :: [instance_info()]
  def get_instances(slug, opts \\ []) do
    case get_agent(slug, opts) do
      nil -> []
      agent -> agent.running_instances || []
    end
  end

  @doc """
  Returns a specific running instance for an agent slug and instance id.
  """
  @spec get_instance(String.t(), String.t(), keyword()) :: instance_info() | nil
  def get_instance(slug, instance_id, opts \\ []) when is_binary(instance_id) do
    get_instances(slug, opts)
    |> Enum.find(&(&1.id == instance_id))
  end

  @doc """
  Lists agents discovered via `Jido.Discovery` (static catalog).

  These are agent modules compiled into the release, regardless of
  whether they are currently running.
  """
  @spec list_discovered_agents(keyword()) :: [agent_info()]
  def list_discovered_agents(opts \\ []) do
    scope = Keyword.get(opts, :scope, Scope.default_scope()) |> Scope.normalize_scope()

    case scope do
      :all ->
        list_discovered_agents_all_nodes()

      {:node, node} ->
        if node == Node.self() do
          list_discovered_agents_local()
        else
          case RPC.call({:node, node}, __MODULE__, :list_discovered_agents_local, []) do
            {:ok, agents} when is_list(agents) -> agents
            _ -> []
          end
        end
    end
  end

  @doc false
  @spec list_discovered_agents_local() :: [agent_info()]
  def list_discovered_agents_local do
    discovered = list_discovered_agents_from_catalog()
    fallback = list_discovered_agents_from_behaviour()

    merge_discovered_agents(discovered, fallback)
  end

  @doc """
  Lists currently running agent processes from a Jido instance.
  """
  @spec list_running_agents(module() | nil) :: [{String.t(), pid()}]
  def list_running_agents(nil), do: []

  def list_running_agents(jido_instance) do
    Jido.list_agents(jido_instance)
  rescue
    _ -> []
  catch
    :exit, _ -> []
  end

  @doc """
  Returns the count of running agents for a Jido instance.
  """
  @spec running_count(module() | nil, keyword()) :: non_neg_integer()
  def running_count(jido_instance, opts \\ []) do
    scope = Keyword.get(opts, :scope, Scope.default_scope()) |> Scope.normalize_scope()

    case scope do
      :all ->
        Scope.available_nodes()
        |> Enum.map(&running_count_for_node(&1, jido_instance))
        |> Enum.sum()

      {:node, node} ->
        if node == Node.self() do
          running_count_local(jido_instance)
        else
          running_count_for_node(node, jido_instance)
        end
    end
  end

  @doc false
  @spec running_count_local(module() | nil) :: non_neg_integer()
  def running_count_local(nil), do: 0

  def running_count_local(jido_instance) do
    Jido.agent_count(jido_instance)
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  defp list_agents_all_nodes(opts) do
    Scope.available_nodes()
    |> Enum.flat_map(fn node ->
      case list_agents_for_node(node, opts) do
        agents when is_list(agents) -> annotate_node(agents, node)
        _ -> []
      end
    end)
    |> merge_cluster_agents()
    |> Enum.sort_by(fn a -> {status_sort(a.status), a.name} end)
  end

  defp list_discovered_agents_all_nodes do
    Scope.available_nodes()
    |> Enum.flat_map(fn node ->
      case list_discovered_for_node(node) do
        agents when is_list(agents) -> agents
        _ -> []
      end
    end)
    |> Enum.reduce(%{}, fn agent, acc ->
      Map.update(acc, agent.module, agent, &merge_cluster_agent_metadata(&1, agent))
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.name)
  end

  defp list_agents_for_node(node, opts) do
    if node == Node.self() do
      list_agents_local(opts)
    else
      case RPC.call({:node, node}, __MODULE__, :list_agents_local, [opts]) do
        {:ok, agents} when is_list(agents) -> agents
        _ -> []
      end
    end
  end

  defp list_discovered_for_node(node) do
    if node == Node.self() do
      list_discovered_agents_local()
    else
      case RPC.call({:node, node}, __MODULE__, :list_discovered_agents_local, []) do
        {:ok, agents} when is_list(agents) -> agents
        _ -> []
      end
    end
  end

  defp running_count_for_node(node, jido_instance) do
    if node == Node.self() do
      running_count_local(jido_instance)
    else
      case RPC.call({:node, node}, __MODULE__, :running_count_local, [jido_instance]) do
        {:ok, count} when is_integer(count) and count >= 0 -> count
        _ -> 0
      end
    end
  end

  defp annotate_node(agents, node) when is_list(agents) do
    Enum.map(agents, fn agent ->
      running_instances =
        Enum.map(agent.running_instances || [], fn instance ->
          Map.put_new(instance, :node, node)
        end)

      Map.put(agent, :running_instances, running_instances)
    end)
  end

  defp merge_cluster_agents(agents) do
    agents
    |> Enum.reduce(%{}, fn agent, acc ->
      Map.update(acc, agent.module, agent, fn existing ->
        merge_cluster_agent(existing, agent)
      end)
    end)
    |> Map.values()
  end

  defp merge_cluster_agent(left, right) do
    running_instances =
      merge_running_instances(left.running_instances || [], right.running_instances || [])

    left
    |> merge_cluster_agent_metadata(right)
    |> Map.put(:running_instances, running_instances)
    |> Map.put(:status, if(running_instances == [], do: :available, else: :running))
  end

  defp merge_cluster_agent_metadata(left, right) do
    %{
      left
      | name: present_value(left.name, right.name),
        description: present_value(left.description, right.description),
        slug: present_value(left.slug, right.slug),
        category: present_value(left.category, right.category),
        tags: Enum.uniq(List.wrap(left.tags) ++ List.wrap(right.tags))
    }
  end

  defp present_value(value, fallback) when value in [nil, ""], do: fallback
  defp present_value(value, _fallback), do: value

  defp merge_running_instances(left, right) do
    (left ++ right)
    |> Enum.reduce(%{}, fn instance, acc ->
      key = {instance.id, Map.get(instance, :node)}
      Map.put(acc, key, instance)
    end)
    |> Map.values()
    |> Enum.sort_by(fn instance -> {Map.get(instance, :node) || Node.self(), instance.id} end)
  end

  defp merge_agents(discovered, running) do
    running_map =
      Enum.reduce(running, %{}, fn {id, pid}, acc ->
        case agent_module(pid) do
          nil -> acc
          mod -> Map.update(acc, mod, [%{id: id, pid: pid}], &[%{id: id, pid: pid} | &1])
        end
      end)

    discovered_modules = MapSet.new(discovered, & &1.module)

    discovered_agents =
      Enum.map(discovered, fn agent ->
        instances = Map.get(running_map, agent.module, [])

        %{
          agent
          | status: if(instances == [], do: :available, else: :running),
            running_instances: instances,
            pid: nil,
            id: nil
        }
      end)

    running_only_agents =
      running_map
      |> Enum.reject(fn {module, _instances} -> MapSet.member?(discovered_modules, module) end)
      |> Enum.map(fn {module, instances} ->
        module_to_agent_info(module)
        |> Map.put(:status, :running)
        |> Map.put(:running_instances, instances)
      end)

    (discovered_agents ++ running_only_agents)
    |> Enum.sort_by(fn a -> {status_sort(a.status), a.name} end)
  end

  defp list_discovered_agents_from_catalog do
    Jido.Discovery.list_agents()
    |> Enum.map(&metadata_to_agent_info/1)
  rescue
    _ -> []
  end

  # Fallback for agents that don't export __agent_metadata__/0 yet.
  # This keeps Studio useful with current jido_ai examples and older agents.
  defp list_discovered_agents_from_behaviour do
    loaded_applications()
    |> Enum.flat_map(&modules_for/1)
    |> Enum.uniq()
    |> Enum.filter(&jido_agent_module?/1)
    |> Enum.map(&module_to_agent_info/1)
  end

  defp merge_discovered_agents(discovered, fallback) do
    fallback
    |> Map.new(&{&1.module, &1})
    |> Map.merge(Map.new(discovered, &{&1.module, &1}))
    |> Map.values()
  end

  defp loaded_applications do
    Application.loaded_applications()
    |> Enum.map(fn {app, _description, _vsn} -> app end)
  end

  defp modules_for(app) do
    case :application.get_key(app, :modules) do
      {:ok, modules} -> modules
      _ -> []
    end
  end

  defp jido_agent_module?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and
      module.module_info(:attributes)
      |> Keyword.get(:behaviour, [])
      |> Enum.member?(Jido.Agent)
  rescue
    _ -> false
  end

  defp module_to_agent_info(module) do
    %{
      module: module,
      name: metadata_value(module, :name, module_name(module)),
      description: metadata_value(module, :description, ""),
      slug: module_slug(module),
      category: metadata_value(module, :category, nil),
      tags: metadata_tags(module),
      status: :available,
      running_instances: [],
      pid: nil,
      id: nil
    }
  end

  defp metadata_to_agent_info(meta) do
    %{
      module: meta[:module],
      name: meta[:name] || module_name(meta[:module]),
      description: meta[:description] || "",
      slug: meta[:slug],
      category: meta[:category],
      tags: meta[:tags] || [],
      status: :available,
      running_instances: [],
      pid: nil,
      id: nil
    }
  end

  defp metadata_value(module, fun, default) do
    if function_exported?(module, fun, 0) do
      apply(module, fun, [])
    else
      default
    end
  rescue
    _ -> default
  end

  defp metadata_tags(module) do
    case metadata_value(module, :tags, []) do
      tags when is_list(tags) -> tags
      _ -> []
    end
  end

  defp module_slug(module) do
    module
    |> Atom.to_string()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.url_encode64(padding: false)
    |> binary_part(0, 8)
  end

  defp agent_module(pid) when is_pid(pid) do
    case Jido.AgentServer.state(pid) do
      {:ok, %{agent_module: module}} when is_atom(module) -> module
      {:ok, state} -> fallback_agent_module(state)
      _ -> nil
    end
  rescue
    _ -> nil
  catch
    :exit, _ -> nil
  end

  defp fallback_agent_module(%{agent: %{__struct__: module}}) when is_atom(module), do: module
  defp fallback_agent_module(_), do: nil

  defp status_sort(:running), do: 0
  defp status_sort(:available), do: 1
  defp status_sort(_), do: 2

  defp module_name(mod) when is_atom(mod) do
    mod
    |> Module.split()
    |> List.last()
    |> Macro.underscore()
    |> Naming.humanize()
  end

  defp module_name(_), do: "Unknown"
end
