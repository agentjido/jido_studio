defmodule JidoStudio.AgentRegistry do
  @moduledoc """
  Agent discovery for Jido Studio.

  Combines static module discovery (via `Jido.Discovery`) with runtime
  process listing (via a configured Jido instance) to provide a unified
  view of all agents in the system.
  """

  require Logger
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
  """
  @spec list_agents(keyword()) :: [agent_info()]
  def list_agents(opts \\ []) do
    discovered = list_discovered_agents()
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
  @spec list_discovered_agents() :: [agent_info()]
  def list_discovered_agents do
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
  @spec running_count(module() | nil) :: non_neg_integer()
  def running_count(nil), do: 0

  def running_count(jido_instance) do
    Jido.agent_count(jido_instance)
  rescue
    _ -> 0
  catch
    :exit, _ -> 0
  end

  defp merge_agents(discovered, running) do
    running_map =
      Enum.reduce(running, %{}, fn {id, pid}, acc ->
        case agent_module(pid) do
          nil -> acc
          mod -> Map.update(acc, mod, [%{id: id, pid: pid}], &[%{id: id, pid: pid} | &1])
        end
      end)

    discovered
    |> Enum.map(fn agent ->
      instances = Map.get(running_map, agent.module, [])

      %{
        agent
        | status: if(instances == [], do: :available, else: :running),
          running_instances: instances,
          pid: nil,
          id: nil
      }
    end)
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
