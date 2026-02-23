defmodule JidoStudio.Setup do
  @moduledoc false

  alias JidoStudio.AgentRegistry
  alias JidoStudio.Cluster.RPC
  alias JidoStudio.ScopeQuery
  alias JidoStudio.Setup.Profiles
  alias JidoStudio.Threads.Storage, as: ThreadsStorage

  @chat_env_vars ["ANTHROPIC_API_KEY", "CLAUDE_API_KEY", "OPENAI_API_KEY", "GROQ_API_KEY"]

  @spec build(keyword()) :: map()
  def build(opts \\ []) do
    scope = Keyword.get(opts, :scope, :all)
    jido_instance = Keyword.get(opts, :jido_instance)
    prefix = Keyword.get(opts, :prefix, "")
    runtime_key = Keyword.get(opts, :runtime_key)
    node_param = Keyword.get(opts, :node_param, "all")
    rpc_fun = Keyword.get(opts, :rpc_fun, &RPC.call/4)
    settings_path = page_path(prefix, "/settings", runtime_key, node_param)
    agents_path = page_path(prefix, "/agents", runtime_key, node_param)

    agents =
      Keyword.get(opts, :agents) ||
        AgentRegistry.list_agents(jido_instance: jido_instance, scope: scope)

    runtime_check = runtime_check(jido_instance, scope, settings_path, rpc_fun)
    persistence_check = persistence_check(jido_instance, settings_path)
    realtime_check = realtime_check(settings_path)
    chat_check = chat_check(settings_path, agents_path)

    smoke_path = runnable_path(prefix, runtime_key, node_param, agents)
    smoke_check = smoke_check(runtime_check, agents, smoke_path)

    checks = [runtime_check, persistence_check, realtime_check, chat_check, smoke_check]

    flags = %{
      runtime_ready?: runtime_check.status in [:pass, :warn],
      durable_persistence?: persistence_check[:durable?] == true,
      realtime_event_driven?: realtime_check.status == :pass,
      chat_keys_present?: chat_check[:keys_present?] == true,
      smoke_ready?: smoke_check.status in [:pass, :warn]
    }

    %{
      checks: checks,
      core_ready?: core_ready?(checks),
      recommended_improvements: recommended_improvements(checks),
      flags: flags,
      active_profile_key: Profiles.infer_profile(flags),
      profiles: Profiles.profiles()
    }
  end

  @spec check_statuses(map()) :: map()
  def check_statuses(%{checks: checks}) when is_list(checks) do
    Enum.reduce(checks, %{}, fn check, acc ->
      Map.put(acc, check.id, status_key(check.status))
    end)
  end

  def check_statuses(_), do: %{}

  @spec status_key(atom()) :: String.t()
  def status_key(:pass), do: "pass"
  def status_key(:warn), do: "warn"
  def status_key(:fail), do: "fail"
  def status_key(:info), do: "info"
  def status_key(:ok), do: "pass"
  def status_key(:warning), do: "warn"
  def status_key(_), do: "info"

  @spec status_label(atom()) :: String.t()
  def status_label(:pass), do: "Pass"
  def status_label(:warn), do: "Warn"
  def status_label(:fail), do: "Fail"
  def status_label(:info), do: "Info"
  def status_label(:ok), do: "Pass"
  def status_label(:warning), do: "Warn"
  def status_label(_), do: "Info"

  @spec status_badge_variant(atom()) :: atom()
  def status_badge_variant(:pass), do: :success
  def status_badge_variant(:warn), do: :warning
  def status_badge_variant(:fail), do: :error
  def status_badge_variant(:info), do: :default
  def status_badge_variant(:ok), do: :success
  def status_badge_variant(:warning), do: :warning
  def status_badge_variant(_), do: :default

  @spec runtime_check(module() | nil, term(), String.t(), function()) :: map()
  defp runtime_check(nil, _scope, settings_path, _rpc_fun) do
    %{
      id: :runtime_connected,
      label: "Runtime Connected",
      status: :fail,
      detail: "No Jido runtime configured. Add `config :jido_studio, jido_instance: MyApp.Jido`.",
      required?: true,
      recommendation: "Add a configured runtime and re-test setup.",
      actions: [
        navigate_action("Open config snippet", settings_path),
        event_action("Re-test", "retest_setup")
      ]
    }
  end

  defp runtime_check(jido_instance, scope, settings_path, rpc_fun)
       when is_atom(jido_instance) do
    case rpc_fun.(scope, Jido, :agent_count, [jido_instance]) do
      {:ok, count} when is_integer(count) and count >= 0 ->
        %{
          id: :runtime_connected,
          label: "Runtime Connected",
          status: :pass,
          detail: "Runtime reachable. Running agent count: #{count}.",
          required?: true,
          recommendation: nil,
          actions: [
            event_action("Re-test", "retest_setup"),
            navigate_action("Open config snippet", settings_path)
          ]
        }

      {:ok, node_results} when is_list(node_results) ->
        summarize_runtime_results(node_results, settings_path)

      {:error, reason} ->
        %{
          id: :runtime_connected,
          label: "Runtime Connected",
          status: :fail,
          detail: "Runtime check failed: #{format_rpc_error(reason)}",
          required?: true,
          recommendation: "Verify runtime module and node connectivity.",
          actions: [
            navigate_action("Open config snippet", settings_path),
            event_action("Re-test", "retest_setup")
          ]
        }

      _ ->
        %{
          id: :runtime_connected,
          label: "Runtime Connected",
          status: :fail,
          detail: "Runtime check returned an unexpected response.",
          required?: true,
          recommendation: "Verify runtime module and node connectivity.",
          actions: [
            navigate_action("Open config snippet", settings_path),
            event_action("Re-test", "retest_setup")
          ]
        }
    end
  end

  defp summarize_runtime_results(results, settings_path) do
    reachable = Enum.filter(results, &Map.get(&1, :ok?))
    unreachable = Enum.reject(results, &Map.get(&1, :ok?))

    count =
      reachable
      |> Enum.map(&Map.get(&1, :value))
      |> Enum.filter(&is_integer/1)
      |> Enum.sum()

    cond do
      reachable == [] ->
        detail =
          unreachable
          |> List.first()
          |> case do
            %{error: reason} -> "Runtime is unreachable: #{format_rpc_error(reason)}"
            _ -> "Runtime is unreachable in the selected scope."
          end

        %{
          id: :runtime_connected,
          label: "Runtime Connected",
          status: :fail,
          detail: detail,
          required?: true,
          recommendation: "Verify runtime module and node connectivity.",
          actions: [
            navigate_action("Open config snippet", settings_path),
            event_action("Re-test", "retest_setup")
          ]
        }

      unreachable == [] ->
        %{
          id: :runtime_connected,
          label: "Runtime Connected",
          status: :pass,
          detail:
            "Runtime reachable across #{length(reachable)} node(s). Running agent count: #{count}.",
          required?: true,
          recommendation: nil,
          actions: [
            event_action("Re-test", "retest_setup"),
            navigate_action("Open config snippet", settings_path)
          ]
        }

      true ->
        %{
          id: :runtime_connected,
          label: "Runtime Connected",
          status: :warn,
          detail:
            "Runtime reachable on #{length(reachable)} node(s), with #{length(unreachable)} node(s) unavailable.",
          required?: true,
          recommendation:
            "Investigate unavailable nodes in Diagnostics before production triage.",
          actions: [
            navigate_action("Open config snippet", settings_path),
            event_action("Re-test", "retest_setup")
          ]
        }
    end
  end

  defp persistence_check(jido_instance, settings_path) do
    enabled? = ThreadsStorage.persistence_enabled?()
    mode = ThreadsStorage.thread_storage_mode()

    {adapter, storage_path, durable?} =
      case ThreadsStorage.resolve_storage(jido_instance: jido_instance) do
        {:ok, {resolved_adapter, adapter_opts}} ->
          path =
            case Keyword.get(adapter_opts, :path) do
              value when is_binary(value) and value != "" -> value
              _ -> "n/a"
            end

          {resolved_adapter, path, enabled? and resolved_adapter != Jido.Storage.ETS}

        _ ->
          {"unavailable", "n/a", false}
      end

    {status, detail, recommendation} =
      cond do
        enabled? and durable? ->
          {:pass,
           "Durable persistence enabled (mode: #{mode}, adapter: #{inspect(adapter)}, path: #{storage_path}).",
           nil}

        enabled? ->
          {:warn,
           "Ephemeral persistence in use (mode: #{mode}, adapter: #{inspect(adapter)}). Data resets on restart.",
           "Use the Team Durable Ops profile for incident-safe storage."}

        true ->
          {:warn, "Thread persistence is disabled; workspace state is ephemeral.",
           "Enable persistence or use a durable profile for shared operations."}
      end

    %{
      id: :persistence_selected,
      label: "Persistence Selected",
      status: status,
      detail: detail,
      required?: true,
      durable?: durable?,
      recommendation: recommendation,
      actions: [
        event_action("Use durable profile", "select_setup_profile", "team_durable_ops"),
        navigate_action("Keep dev mode", settings_path)
      ]
    }
  end

  defp realtime_check(settings_path) do
    live_ops_enabled? = JidoStudio.LiveOps.enabled?()
    presence? = JidoStudio.LiveOps.presence_available?()

    {status, detail, recommendation} =
      cond do
        live_ops_enabled? and presence? ->
          {:pass, "Realtime updates are event-driven with presence integration.", nil}

        live_ops_enabled? ->
          {:warn, "Presence integration is unavailable. Polling fallback is active.",
           "Enable presence integration for multi-operator realtime visibility."}

        true ->
          {:warn, "Live Ops is disabled; realtime updates are limited.",
           "Enable Live Ops and presence for richer diagnostics."}
      end

    %{
      id: :realtime_enabled,
      label: "Realtime Enabled",
      status: status,
      detail: detail,
      required?: true,
      recommendation: recommendation,
      actions: [
        event_action("Enable realtime", "select_setup_profile", "team_durable_ops"),
        navigate_action("Continue with polling", settings_path)
      ]
    }
  end

  defp chat_check(settings_path, agents_path) do
    keys_present? =
      Enum.any?(@chat_env_vars, fn var ->
        case System.get_env(var) do
          value when is_binary(value) -> String.trim(value) != ""
          _ -> false
        end
      end)

    {status, detail, recommendation} =
      if keys_present? do
        {:pass, "At least one chat provider key is configured.", nil}
      else
        {:info, "No chat provider key detected. Interact workflows remain available.",
         "Add provider keys only if chat workflows are required."}
      end

    %{
      id: :chat_credentials,
      label: "Chat Credentials (Optional)",
      status: status,
      detail: detail,
      required?: false,
      keys_present?: keys_present?,
      recommendation: recommendation,
      actions: [
        navigate_action("Configure provider keys", settings_path),
        navigate_action("Use Interact (non-chat)", agents_path)
      ]
    }
  end

  defp smoke_check(runtime_check, agents, smoke_path) do
    running_instances =
      agents
      |> Enum.reduce(0, fn agent, acc ->
        acc + length(Map.get(agent, :running_instances, []))
      end)

    {status, detail, recommendation} =
      cond do
        runtime_check.status == :fail ->
          {:fail, "Smoke check blocked because runtime connectivity failed.",
           "Fix runtime connectivity before running smoke interactions."}

        running_instances > 0 ->
          {:pass, "Smoke path ready. #{running_instances} running instance(s) detected.", nil}

        agents != [] ->
          {:warn, "Agents are discoverable, but no running instance is available yet.",
           "Start one instance and run an interaction to validate the full loop."}

        true ->
          {:fail, "No agents discovered in the selected runtime/scope.",
           "Confirm discovery and runtime configuration, then re-test."}
      end

    %{
      id: :smoke_test,
      label: "Smoke Test",
      status: status,
      detail: detail,
      required?: true,
      recommendation: recommendation,
      actions: [
        navigate_action("Run smoke interaction", smoke_path),
        event_action("Re-test", "retest_setup")
      ]
    }
  end

  defp core_ready?(checks) do
    Enum.all?(checks, fn check ->
      if check.required? do
        check.status != :fail
      else
        true
      end
    end)
  end

  defp recommended_improvements(checks) do
    checks
    |> Enum.filter(&(&1.status in [:warn, :info]))
    |> Enum.map(fn check ->
      %{
        id: check.id,
        label: check.label,
        status: check.status,
        detail: check.detail,
        recommendation: check[:recommendation] || check.detail
      }
    end)
  end

  defp page_path(prefix, suffix, runtime_key, node_param) do
    ScopeQuery.with_scope_query(prefix <> suffix, runtime_key, node_param)
  end

  defp runnable_path(prefix, runtime_key, node_param, agents) when is_list(agents) do
    running =
      Enum.find_value(agents, fn agent ->
        slug = agent[:slug]

        instance_id =
          agent
          |> Map.get(:running_instances, [])
          |> Enum.find_value(&Map.get(&1, :id))

        if is_binary(slug) and is_binary(instance_id) do
          "#{prefix}/agents/#{slug}/#{URI.encode_www_form(instance_id)}"
        end
      end)

    module_path =
      Enum.find_value(agents, fn agent ->
        slug = agent[:slug]

        if is_binary(slug) do
          "#{prefix}/agents/#{slug}"
        end
      end)

    cond do
      is_binary(running) ->
        ScopeQuery.with_scope_query(running, runtime_key, node_param)

      is_binary(module_path) ->
        ScopeQuery.with_scope_query(module_path, runtime_key, node_param)

      true ->
        page_path(prefix, "/agents", runtime_key, node_param)
    end
  end

  defp runnable_path(prefix, runtime_key, node_param, _agents) do
    page_path(prefix, "/agents", runtime_key, node_param)
  end

  defp format_rpc_error(%{kind: :timeout}), do: "timeout"
  defp format_rpc_error(%{kind: :nodedown}), do: "node down"
  defp format_rpc_error(%{kind: :exception, reason: reason}), do: to_string(reason)
  defp format_rpc_error(%{reason: reason}), do: inspect(reason)
  defp format_rpc_error(reason), do: inspect(reason)

  defp navigate_action(label, path) when is_binary(label) and is_binary(path) do
    %{kind: :navigate, label: label, path: path}
  end

  defp event_action(label, event, value \\ nil)
       when is_binary(label) and is_binary(event) do
    %{
      kind: :event,
      label: label,
      event: event
    }
    |> maybe_put_value(value)
  end

  defp maybe_put_value(action, nil), do: action
  defp maybe_put_value(action, value), do: Map.put(action, :value, to_string(value))
end
