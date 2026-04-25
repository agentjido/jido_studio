defmodule JidoStudio.Live.AgentsLive.ShowState do
  @moduledoc false

  import Phoenix.Component, only: [assign: 3]

  alias JidoStudio.AgentInteractions
  alias JidoStudio.AgentRegistry
  alias JidoStudio.Agents.Introspection
  alias JidoStudio.Agents.StarterOperations
  alias JidoStudio.Chat.Runtime, as: ChatRuntime
  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Display
  alias JidoStudio.Live.AgentsLive.Routes
  alias JidoStudio.Live.AgentsLive.Support
  alias JidoStudio.Observability.Incidents
  alias JidoStudio.Presenters.Default

  @default_model "claude-sonnet-4-5"

  def apply_show(socket, slug, params, opts \\ []) do
    jido_instance = socket.assigns[:jido_instance]
    requested_instance_id = Map.get(params, "instance_id")
    start_modal_requested? = start_modal_requested?(params)
    requested_view_mode = Support.parse_instance_view_mode_param(Map.get(params, "view"))
    requested_workbench_tab = Support.requested_workbench_tab(params)
    explicit_workbench_tab? = not is_nil(requested_workbench_tab)
    requested_section_param = Map.get(params, "section")
    requested_section = Support.parse_instance_section(requested_section_param)

    instance_view_mode =
      case requested_view_mode do
        mode when mode in [:basic, :advanced] ->
          mode

        _ ->
          if legacy_advanced_view_intent?(
               params,
               requested_section_param,
               requested_workbench_tab
             ) do
            :advanced
          else
            :basic
          end
      end

    scope_filters =
      Support.merge_scope_filters(socket.assigns[:scope_filters], Map.get(params, "scope"))

    ensure_workspace_state = Keyword.fetch!(opts, :ensure_workspace_state)
    maybe_subscribe_live_ops = Keyword.fetch!(opts, :maybe_subscribe_live_ops)
    refresh_instance_observability = Keyword.fetch!(opts, :refresh_instance_observability)
    maybe_track_followed_viewer = Keyword.fetch!(opts, :maybe_track_followed_viewer)

    case AgentRegistry.get_agent(
           slug,
           jido_instance: jido_instance,
           scope: socket.assigns[:cluster_scope]
         ) do
      nil ->
        socket
        |> Phoenix.LiveView.put_flash(:error, "Agent not found")
        |> Phoenix.LiveView.push_navigate(to: scoped_path("#{socket.assigns.prefix}/agents"))

      agent ->
        running_instances = agent.running_instances || []
        presenter = JidoStudio.PresenterResolver.resolve(agent.module)

        instance_runtime_map =
          Map.new(running_instances, fn instance ->
            {instance.id, instance_runtime_details(instance)}
          end)

        selected_instance =
          case requested_instance_id do
            nil ->
              if start_modal_requested? do
                nil
              else
                if JidoStudio.LiveOps.auto_follow_default?() do
                  List.first(running_instances)
                else
                  nil
                end
              end

            id ->
              Enum.find(running_instances, &(&1.id == id))
          end

        active_instance_id =
          if(selected_instance, do: selected_instance.id, else: requested_instance_id)

        active_instance_pid = selected_instance && selected_instance.pid

        runtime_status =
          if selected_instance do
            instance_runtime_map
            |> Map.get(selected_instance.id, %{})
            |> Map.get(:status)
          else
            nil
          end

        instance_cards =
          build_instance_cards(
            presenter,
            agent,
            running_instances,
            instance_runtime_map,
            socket.assigns.prefix,
            instance_view_mode
          )

        start_form_schema = presenter_start_form_schema(presenter, agent)

        traces_path =
          traces_path(socket.assigns.prefix, agent, active_instance_id, active_instance_id)

        observability_preview =
          if selected_instance do
            JidoStudio.Live.AgentsLive.ObservabilityState.load_instance_observability(
              selected_instance.id,
              selected_instance.pid,
              socket.assigns[:trace_preview_limit],
              socket.assigns[:trace_include_agent_debug?]
            )
          else
            %{events: []}
          end

        interaction_model =
          if AgentInteractions.enabled?() do
            Introspection.build(agent.module, %{pid: active_instance_pid},
              events: observability_preview[:events] || []
            )
          else
            Support.empty_interaction_model()
          end

        starter_operations = StarterOperations.list(agent, interaction_model)

        view_model =
          presenter_view_model(
            presenter,
            agent,
            runtime_status,
            instance_id: active_instance_id,
            pid: active_instance_pid,
            debug_enabled: selected_instance && instance_debug_enabled(selected_instance),
            raw_state: runtime_status && runtime_status.raw_state,
            observability_preview: if(selected_instance, do: observability_preview, else: nil),
            traces_path: traces_path
          )

        chat_config =
          presenter_chat_config(
            presenter,
            agent,
            runtime_status,
            instance_id: active_instance_id,
            pid: active_instance_pid,
            supported?: ChatRuntime.supports?(agent.module)
          )

        {chat_enabled, chat_unavailable_reason} =
          resolve_chat_availability(chat_config, runtime_status, active_instance_pid)

        requested_workbench_tab =
          requested_workbench_tab || Support.default_workbench_tab_for_section(requested_section)

        workbench_tab =
          Support.resolve_default_workbench_tab(
            requested_workbench_tab,
            interaction_model,
            chat_enabled
          )

        instance_section =
          if explicit_workbench_tab? do
            Support.section_for_workbench_tab(workbench_tab)
          else
            if Support.workbench_tab_in_section?(workbench_tab, requested_section) do
              requested_section
            else
              Support.section_for_workbench_tab(workbench_tab)
            end
          end

        tabs =
          view_model
          |> Map.get(:tabs, [%{id: :overview, label: "Overview"}])
          |> Support.ordered_detail_tabs()

        socket
        |> assign(:page_title, JidoStudio.Naming.humanize(agent.name))
        |> assign(:agent, agent)
        |> assign(:presenter, presenter)
        |> assign(:running_instances, running_instances)
        |> assign(:instance_cards, instance_cards)
        |> assign(:active_instance_id, active_instance_id)
        |> assign(:followed_instance_id, active_instance_id)
        |> assign(:active_instance_pid, active_instance_pid)
        |> assign(:runtime_status, runtime_status)
        |> assign(:scope_filters, scope_filters)
        |> assign(:instance_view_mode, instance_view_mode)
        |> assign(
          :start_modal_open?,
          start_modal_requested? and socket.assigns[:jido_configured?] == true
        )
        |> assign(
          :instance_debug_enabled?,
          if(selected_instance, do: instance_debug_enabled(selected_instance), else: false)
        )
        |> assign(
          :instance_debug_level,
          if(selected_instance && instance_debug_enabled(selected_instance),
            do: "on",
            else: "off"
          )
        )
        |> assign(:chat_config, chat_config)
        |> assign(:chat_enabled?, chat_enabled)
        |> assign(:chat_unavailable_reason, chat_unavailable_reason)
        |> assign(:interaction_model, interaction_model)
        |> assign(:starter_operations, starter_operations)
        |> assign(:workbench_tab, workbench_tab)
        |> assign(:instance_section, instance_section)
        |> assign(
          :runner_form,
          socket.assigns[:runner_form]
          |> Support.sync_runner_form(interaction_model)
        )
        |> assign(:runner_field_errors, %{})
        |> assign(:runner_result, nil)
        |> assign(:last_run_summary, nil)
        |> assign(:runner_history, Support.current_runner_history(socket, active_instance_id))
        |> assign(:detail_tabs, tabs)
        |> assign(:detail_tab, parse_detail_tab(Map.get(params, "tab"), tabs))
        |> assign(:sections_by_tab, Map.get(view_model, :sections_by_tab, %{}))
        |> assign(:start_form_schema, start_form_schema)
        |> assign(:start_form, Support.default_start_form(start_form_schema))
        |> assign(
          :system_prompt,
          Map.get(view_model, :system_prompt, "No system prompt configured.")
        )
        |> ensure_workspace_state.(agent, active_instance_id)
        |> maybe_subscribe_live_ops.(active_instance_id, scope_filters)
        |> assign(
          :triage_links,
          triage_links(socket.assigns.prefix, active_instance_id, scope_filters)
        )
        |> refresh_instance_observability.()
        |> maybe_track_followed_viewer.()
    end
  end

  def start_modal_requested?(params) when is_map(params) do
    params
    |> Map.get("start")
    |> normalize_start_param()
  end

  def start_modal_requested?(_), do: false

  defp normalize_start_param(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.downcase()

    normalized in ["1", "true", "yes", "on"]
  end

  defp normalize_start_param(value) when is_integer(value), do: value == 1
  defp normalize_start_param(value) when is_boolean(value), do: value
  defp normalize_start_param(_), do: false

  def parse_detail_tab(nil, detail_tabs), do: default_detail_tab(detail_tabs)

  def parse_detail_tab(tab, detail_tabs) when is_binary(tab) do
    case Enum.find(detail_tabs, fn item -> Atom.to_string(item.id) == tab end) do
      nil -> default_detail_tab(detail_tabs)
      item -> item.id
    end
  end

  def parse_detail_tab(_tab, detail_tabs), do: default_detail_tab(detail_tabs)

  def default_detail_tab([first | _]), do: first.id
  def default_detail_tab(_), do: :overview

  def strategy_model(module, default_model \\ @default_model)

  def strategy_model(module, default_model) when is_atom(module) do
    module
    |> strategy_opts()
    |> Keyword.get(:model, default_model)
    |> Display.model_label(default_model)
  end

  def strategy_model(_, default_model), do: default_model

  def strategy_opts(module) do
    if function_exported?(module, :strategy_opts, 0) do
      module.strategy_opts()
    else
      []
    end
  rescue
    _ -> []
  end

  def presenter_view_model(presenter, agent, runtime_status, opts) do
    if runtime_status do
      presenter.runtime(agent, runtime_status, opts)
    else
      presenter.static(agent)
    end
  rescue
    _ ->
      if runtime_status do
        Default.runtime(agent, runtime_status, opts)
      else
        Default.static(agent)
      end
  end

  def instance_runtime_status(nil), do: nil

  def instance_runtime_status(%{pid: pid}) when is_pid(pid) do
    case Jido.AgentServer.status(pid) do
      {:ok, status} -> status
      _ -> nil
    end
  rescue
    _ -> nil
  end

  def instance_debug_enabled(%{pid: pid}) when is_pid(pid) do
    case Jido.AgentServer.state(pid) do
      {:ok, %{debug: enabled}} when is_boolean(enabled) -> enabled
      _ -> false
    end
  rescue
    _ -> false
  end

  def instance_debug_enabled(_), do: false

  def agent_module_path(prefix, agent), do: scoped_path("#{prefix}/agents/#{agent.slug}")

  def agent_instance_path(prefix, agent, instance_id, section \\ :play, view_mode \\ nil) do
    Routes.workbench_section_path(prefix, agent, instance_id, section, view_mode)
  end

  def instance_links(
        prefix,
        agent,
        running_instances,
        active_instance_id,
        section,
        view_mode \\ nil
      ) do
    links =
      Enum.map(running_instances, fn instance ->
        %{
          id: instance.id,
          path: agent_instance_path(prefix, agent, instance.id, section, view_mode)
        }
      end)

    if is_binary(active_instance_id) and not Enum.any?(links, &(&1.id == active_instance_id)) do
      links ++
        [
          %{
            id: active_instance_id,
            path: agent_instance_path(prefix, agent, active_instance_id, section, view_mode)
          }
        ]
    else
      links
    end
  end

  def traces_path(prefix, agent, instance_id, agent_id) do
    query =
      [
        {"agent_slug", agent.slug},
        {"agent_module", inspect(agent.module)},
        {"instance_id", instance_id},
        {"agent_id", agent_id}
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
      |> URI.encode_query()

    if query == "" do
      scoped_path("#{prefix}/traces")
    else
      scoped_path("#{prefix}/traces?#{query}")
    end
  end

  def triage_links(prefix, instance_id, scope_filters) when is_binary(instance_id) do
    scope_params = scope_query_params(scope_filters)

    incident =
      Incidents.latest_for_agent(
        instance_id,
        Map.merge(%{agent_id: instance_id, range: "24h"}, scope_params)
      )

    latest_incident_path =
      if is_map(incident) and is_binary(incident[:incident_id]) do
        scoped_path(
          prefix <>
            "/traces?" <>
            URI.encode_query(Map.put(scope_params, "incident_id", incident[:incident_id]))
        )
      else
        nil
      end

    failures_params =
      scope_params
      |> Map.put("agent_id", instance_id)
      |> Map.put("status", "error")
      |> Map.put("error_only", "true")

    snapshot_params =
      scope_params
      |> Map.put("agent_id", instance_id)
      |> Map.put("range", "1h")

    %{
      latest_incident_path: latest_incident_path,
      failures_path: scoped_path(prefix <> "/actions?" <> URI.encode_query(failures_params)),
      snapshot_path: scoped_path(prefix <> "/signals?" <> URI.encode_query(snapshot_params))
    }
  rescue
    _ ->
      %{}
  end

  def triage_links(_prefix, _instance_id, _scope_filters), do: %{}

  def scope_query_params(scope_filters) when is_map(scope_filters) do
    %{}
    |> maybe_put_query("project_id", Support.normalize_scope_value(scope_filters.project_id))
    |> maybe_put_query("user_id", Support.normalize_scope_value(scope_filters.user_id))
  end

  def scope_query_params(_), do: %{}

  def maybe_put_query(params, _key, nil), do: params
  def maybe_put_query(params, key, value), do: Map.put(params, key, value)

  def active_instance_path(prefix, %{agent_slug: slug, instance_id: instance_id})
      when is_binary(prefix) and is_binary(slug) and is_binary(instance_id) do
    scoped_path("#{prefix}/agents/#{slug}/#{URI.encode_www_form(instance_id)}/play")
  end

  def active_instance_path(_prefix, _row), do: nil

  def scoped_path(path) do
    Scope.with_scope_query(path, Scope.current_node_param())
  end

  def status_badge_variant(status) when status in ["running", :running], do: :success
  def status_badge_variant(status) when status in ["idle", :idle], do: :info
  def status_badge_variant(status) when status in ["error", :error], do: :error
  def status_badge_variant(status) when status in ["interrupted", :interrupted], do: :warning
  def status_badge_variant(_), do: :default

  def datetime_to_unix_ms(%DateTime{} = datetime), do: DateTime.to_unix(datetime, :millisecond)
  def datetime_to_unix_ms(_), do: nil

  def format_datetime(%DateTime{} = datetime) do
    Calendar.strftime(datetime, "%Y-%m-%d %H:%M:%S")
  end

  def format_datetime(_), do: "n/a"

  def format_uptime(ms) when is_integer(ms) and ms >= 0 do
    total_seconds = div(ms, 1_000)
    hours = div(total_seconds, 3_600)
    minutes = div(rem(total_seconds, 3_600), 60)
    seconds = rem(total_seconds, 60)

    cond do
      hours > 0 ->
        "#{hours}h #{minutes}m"

      minutes > 0 ->
        "#{minutes}m #{seconds}s"

      true ->
        "#{seconds}s"
    end
  end

  def format_uptime(_), do: "n/a"

  def fetch_jido_instance(socket) do
    case resolve_jido_instance(socket.assigns[:jido_instance]) do
      instance when is_atom(instance) -> {:ok, instance}
      _ -> {:error, "No Jido instance configured for this Studio mount."}
    end
  end

  def resolve_jido_instance(nil), do: Application.get_env(:jido_studio, :jido_instance)
  def resolve_jido_instance(value), do: value

  def build_instance_cards(
        presenter,
        agent,
        running_instances,
        instance_runtime_map,
        prefix,
        view_mode \\ nil
      ) do
    Enum.map(running_instances, fn instance ->
      runtime = Map.get(instance_runtime_map, instance.id, %{})
      status = Map.get(runtime, :status)
      debug_enabled = Map.get(runtime, :debug_enabled, false)

      summary =
        presenter_instance_summary(
          presenter,
          agent,
          instance,
          status,
          debug_enabled: debug_enabled,
          instance_id: instance.id,
          pid: instance.pid
        )

      %{
        id: instance.id,
        path: agent_instance_path(prefix, agent, instance.id, :play, view_mode),
        traces_path: traces_path(prefix, agent, instance.id, instance.id),
        summary: summary
      }
    end)
  end

  def legacy_advanced_view_intent?(params, requested_section, requested_workbench_tab)
      when is_map(params) do
    section_advanced? =
      requested_section
      |> Support.parse_instance_section()
      |> case do
        :observe -> true
        :configure -> true
        _ -> false
      end

    section_advanced? or
      not is_nil(requested_workbench_tab) or
      is_binary(Map.get(params, "panel")) or
      is_binary(Map.get(params, "tab"))
  end

  def legacy_advanced_view_intent?(_, _, _), do: false

  def instance_runtime_details(nil), do: %{status: nil, debug_enabled: false}

  def instance_runtime_details(instance) do
    %{
      status: instance_runtime_status(instance),
      debug_enabled: instance_debug_enabled(instance)
    }
  end

  def presenter_instance_summary(presenter, agent, instance, runtime_status, opts) do
    if function_exported?(presenter, :instance_summary, 4) do
      presenter.instance_summary(agent, instance, runtime_status, opts)
    else
      Default.instance_summary(agent, instance, runtime_status, opts)
    end
  rescue
    _ -> Default.instance_summary(agent, instance, runtime_status, opts)
  end

  def presenter_start_form_schema(presenter, agent) do
    if function_exported?(presenter, :start_form_schema, 1) do
      presenter.start_form_schema(agent)
    else
      Default.start_form_schema(agent)
    end
  rescue
    _ -> Default.start_form_schema(agent)
  end

  def presenter_chat_config(presenter, agent, runtime_status, opts) do
    config =
      if function_exported?(presenter, :chat_config, 3) do
        presenter.chat_config(agent, runtime_status, opts)
      else
        Default.chat_config(agent, runtime_status, opts)
      end

    normalize_chat_config(config, agent, runtime_status, opts)
  rescue
    _ ->
      Default.chat_config(agent, runtime_status, opts)
      |> normalize_chat_config(agent, runtime_status, opts)
  end

  def normalize_chat_config(config, agent, runtime_status, opts) when is_map(config) do
    defaults = Default.chat_config(agent, runtime_status, opts)
    merged = Map.merge(defaults, config)

    %{
      enabled: merged.enabled == true,
      mode: :ask_sync,
      timeout_ms: normalize_chat_timeout(merged.timeout_ms),
      placeholder: to_string(merged.placeholder || defaults.placeholder),
      empty_title: to_string(merged.empty_title || defaults.empty_title),
      empty_description: to_string(merged.empty_description || defaults.empty_description),
      model_label:
        if(is_nil(merged.model_label), do: nil, else: Display.model_label(merged.model_label)),
      streaming_enabled:
        (merged.streaming_enabled == true or defaults.streaming_enabled == true) and
          merged.enabled == true,
      stream_poll_ms: ChatRuntime.stream_poll_ms(stream_poll_ms: merged.stream_poll_ms)
    }
  end

  def normalize_chat_config(_config, agent, runtime_status, opts) do
    presenter_chat_config(Default, agent, runtime_status, opts)
  end

  def default_chat_config do
    %{
      enabled: false,
      mode: :ask_sync,
      timeout_ms: 30_000,
      placeholder: "Enter your message...",
      empty_title: "How can I help you today?",
      empty_description: "Start a message to begin chatting with this instance.",
      model_label: nil,
      streaming_enabled: false,
      stream_poll_ms: 120
    }
  end

  def assign_chat_controls(socket, model_label, chat_provider_options)
      when is_list(chat_provider_options) do
    {provider, model, model_options} =
      chat_controls_from_model(model_label, chat_provider_options)

    socket
    |> Phoenix.Component.assign(:chat_provider_options, chat_provider_options)
    |> Phoenix.Component.assign(:chat_provider, provider)
    |> Phoenix.Component.assign(:chat_model, model)
    |> Phoenix.Component.assign(:chat_model_options, model_options)
  end

  def chat_controls_from_model(model_label, chat_provider_options) do
    {provider, model} = split_model_label(model_label)
    normalize_chat_controls(provider, model, chat_provider_options)
  end

  def normalize_chat_controls(provider, model, chat_provider_options) do
    provider = normalize_provider(provider, chat_provider_options)
    model_options = chat_model_options(provider)
    model = normalize_model(model, model_options)
    {provider, model, model_options}
  end

  def normalize_provider(provider, chat_provider_options) when is_binary(provider) do
    normalized = provider |> String.trim() |> String.downcase()
    if normalized in chat_provider_options, do: normalized, else: "anthropic"
  end

  def normalize_provider(_provider, _chat_provider_options), do: "anthropic"

  def normalize_model(model, model_options) when is_binary(model) do
    candidate = String.trim(model)

    cond do
      model_options != [] and candidate in model_options ->
        candidate

      model_options != [] ->
        hd(model_options)

      candidate == "" ->
        ""

      true ->
        candidate
    end
  end

  def normalize_model(_, model_options) when is_list(model_options) and model_options != [],
    do: hd(model_options)

  def normalize_model(_, _), do: ""

  def split_model_label(label) when is_binary(label) do
    case String.split(label, ":", parts: 2) do
      [provider, model] -> {provider, model}
      [model] -> {"anthropic", model}
      _ -> {"anthropic", "claude-sonnet-4-5"}
    end
  end

  def split_model_label(_), do: {"anthropic", "claude-sonnet-4-5"}

  def chat_model_options("anthropic"),
    do: ["claude-haiku-4-5", "claude-sonnet-4-5", "claude-opus-4-1"]

  def chat_model_options("openai"), do: ["gpt-4.1-mini", "gpt-4.1", "o4-mini"]
  def chat_model_options("groq"), do: ["llama-3.3-70b-versatile", "mixtral-8x7b-32768"]
  def chat_model_options("ollama"), do: ["qwen2.5:7b", "llama3.1:8b", "mistral:7b"]
  def chat_model_options("custom"), do: []
  def chat_model_options(_), do: []

  def normalize_chat_timeout(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0,
    do: timeout_ms

  def normalize_chat_timeout(_), do: 30_000

  def resolve_chat_availability(chat_config, runtime_status, pid) do
    cond do
      not is_pid(pid) ->
        {false, :instance_unavailable}

      chat_config.enabled != true ->
        {false, :unsupported}

      not chat_credentials_available?(chat_config, runtime_status) ->
        {false, :credentials_missing}

      true ->
        {true, nil}
    end
  end

  def chat_credentials_available?(chat_config, runtime_status) do
    provider =
      runtime_status
      |> runtime_model_label()
      |> provider_from_model_label() ||
        chat_config
        |> Map.get(:model_label)
        |> provider_from_model_label()

    provider_credentials_available?(provider)
  end

  def provider_from_model_label(model_label) when is_binary(model_label) do
    case String.split(String.trim(model_label), ":", parts: 2) do
      [provider, _model] ->
        provider
        |> String.trim()
        |> String.downcase()

      _ ->
        nil
    end
  end

  def provider_from_model_label(_), do: nil

  def runtime_model_label(%{snapshot: %{details: details}}) when is_map(details) do
    Display.model_label(details[:model] || details["model"], nil)
  end

  def runtime_model_label(_), do: nil

  def provider_credentials_available?(provider) when provider in [nil, "", "ollama", "custom"],
    do: true

  def provider_credentials_available?("anthropic"),
    do: env_present?(["ANTHROPIC_API_KEY", "CLAUDE_API_KEY"])

  def provider_credentials_available?("openai"), do: env_present?(["OPENAI_API_KEY"])
  def provider_credentials_available?("groq"), do: env_present?(["GROQ_API_KEY"])
  def provider_credentials_available?(_), do: true

  def env_present?(env_vars) when is_list(env_vars) do
    Enum.any?(env_vars, fn var ->
      case System.get_env(var) do
        value when is_binary(value) -> String.trim(value) != ""
        _ -> false
      end
    end)
  end

  def stream_since_entry_count(pid) when is_pid(pid) do
    case ChatRuntime.thread_entry_count(pid) do
      {:ok, count} -> count
      _ -> 0
    end
  end

  def stream_since_entry_count(_), do: 0

  def current_traces_path(socket) do
    case socket.assigns[:agent] do
      nil ->
        nil

      agent ->
        traces_path(
          socket.assigns.prefix,
          agent,
          socket.assigns[:active_instance_id],
          socket.assigns[:active_instance_id]
        )
    end
  end
end
