defmodule JidoStudio.Presenters.Default do
  @moduledoc false
  @behaviour JidoStudio.AgentPresenter

  alias JidoStudio.Chat.Runtime

  @default_model "claude-sonnet-4-5"
  @default_chat_timeout_ms 30_000

  @impl true
  def supports?(_agent_module, _strategy_module), do: true

  @impl true
  def static(agent_info) do
    opts = strategy_opts(agent_info.module)

    %{
      tabs: detail_tabs(),
      sections_by_tab: %{
        overview: [
          section("Status", :badge, status_label(agent_info.status),
            variant: status_variant(agent_info.status)
          ),
          section("Tools", :badges, tools_from_opts(opts)),
          section("Tags", :badges, stringify_list(agent_info.tags || []))
        ],
        model: [
          section("Model", :badge, model_from_opts(opts), variant: :info),
          section("Max Iterations", :text, to_string(max_iterations_from_opts(opts)))
        ],
        memory: [
          section("Memory", :badge, "On", variant: :success),
          section(
            "Notes",
            :text,
            "Threads are ephemeral in this prototype and reset on LiveView reconnect."
          )
        ],
        tracing: [
          section("Tracing", :badge, "Enabled", variant: :info),
          section(
            "Notes",
            :text,
            "Use the Traces button above to inspect telemetry for this agent."
          )
        ]
      },
      system_prompt: system_prompt_from_opts(opts)
    }
  end

  @impl true
  def runtime(agent_info, nil, _opts), do: static(agent_info)

  def runtime(agent_info, status, opts) do
    view_model = static(agent_info)
    details = status.snapshot.details || %{}

    instance_id = Keyword.get(opts, :instance_id)

    overview_sections =
      [
        section("Server Status", :badge, status_label(status.snapshot.status),
          variant: status_variant(status.snapshot.status)
        ),
        maybe_section("Instance", instance_id),
        maybe_section("Iteration", details[:iteration]),
        maybe_section("Queue Length", details[:queue_length])
      ]
      |> Enum.reject(&is_nil/1)

    put_in(
      view_model,
      [:sections_by_tab, :overview],
      view_model.sections_by_tab.overview ++ overview_sections
    )
  end

  @impl true
  def chat_config(agent_info, _runtime_status, opts) do
    model_label = model_from_opts(strategy_opts(agent_info.module))
    pid = Keyword.get(opts, :pid)
    supported? = Keyword.get(opts, :supported?, Runtime.supports?(agent_info.module))
    enabled? = supported? and is_pid(pid)
    streaming_enabled? = enabled? and Runtime.supports_async?(agent_info.module)

    %{
      enabled: enabled?,
      mode: :ask_sync,
      timeout_ms: normalize_timeout(Keyword.get(opts, :timeout_ms, @default_chat_timeout_ms)),
      placeholder: "Enter your message...",
      empty_title: empty_title(enabled?),
      empty_description: empty_description(enabled?, supported?),
      model_label: model_label,
      streaming_enabled: streaming_enabled?,
      stream_poll_ms: Runtime.stream_poll_ms(opts)
    }
  end

  @impl true
  def instance_summary(_agent_info, instance, nil, _opts) do
    %{
      title: short_instance_id(instance[:id]),
      subtitle: instance[:id],
      badges: [%{label: "Unknown", variant: :default}],
      meta: []
    }
  end

  def instance_summary(_agent_info, instance, status, opts) do
    details = status.snapshot.details || %{}
    debug_enabled = debug_enabled(opts, status.raw_state)

    meta =
      [
        {"Queue", to_string(details[:queue_length] || 0)},
        {"Active Requests", to_string(length(details[:active_requests] || []))},
        maybe_meta("Iteration", details[:iteration]),
        maybe_meta("Model", runtime_model(status.raw_state))
      ]
      |> Enum.reject(&is_nil/1)

    %{
      title: short_instance_id(instance[:id]),
      subtitle: instance[:id],
      badges: [
        %{
          label: status_label(status.snapshot.status),
          variant: status_variant(status.snapshot.status)
        },
        %{label: debug_label(debug_enabled), variant: debug_variant(debug_enabled)}
      ],
      meta: meta
    }
  end

  @impl true
  def start_form_schema(_agent_info) do
    [
      %{
        name: "instance_id",
        label: "Instance ID (optional)",
        type: :text,
        default: "",
        placeholder: "weather-agent-dev"
      },
      %{
        name: "debug",
        label: "Enable debug event buffer",
        type: :checkbox,
        default: "false"
      },
      %{
        name: "initial_state_json",
        label: "Initial State (JSON map, optional)",
        type: :textarea_json,
        default: "",
        rows: 6,
        placeholder: "{\n  \"model\": \"anthropic:claude-haiku-4-5\"\n}"
      }
    ]
  end

  defp detail_tabs do
    [
      %{id: :overview, label: "Overview"},
      %{id: :model, label: "Model Settings"},
      %{id: :memory, label: "Memory"},
      %{id: :tracing, label: "Tracing Options"}
    ]
  end

  defp section(title, kind, data, opts \\ []) do
    %{title: title, kind: kind, data: data, variant: Keyword.get(opts, :variant, :default)}
  end

  defp maybe_section(_title, nil), do: nil
  defp maybe_section(title, value), do: section(title, :text, to_string(value))

  defp empty_title(true), do: "How can I help you today?"
  defp empty_title(false), do: "Chat unavailable"

  defp empty_description(true, _supported?) do
    "Send a message to chat with this running instance."
  end

  defp empty_description(false, false) do
    "This agent does not expose ask_sync/3 yet."
  end

  defp empty_description(false, true) do
    "Select a running instance to start chatting."
  end

  defp strategy_opts(module) when is_atom(module) do
    if function_exported?(module, :strategy_opts, 0) do
      module.strategy_opts()
    else
      []
    end
  rescue
    _ -> []
  end

  defp strategy_opts(_), do: []

  defp tools_from_opts(opts) do
    opts
    |> Keyword.get(:tools, [])
    |> Enum.map(&short_module_name/1)
  end

  defp model_from_opts(opts) do
    opts
    |> Keyword.get(:model, @default_model)
    |> to_string()
  end

  defp max_iterations_from_opts(opts) do
    opts
    |> Keyword.get(:max_iterations, 10)
  end

  defp system_prompt_from_opts(opts) do
    opts
    |> Keyword.get(:system_prompt, "No system prompt configured.")
  end

  defp short_module_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> List.last()
    |> to_string()
  end

  defp short_module_name(other), do: inspect(other)

  defp stringify_list(values) do
    Enum.map(values, fn
      value when is_binary(value) -> value
      value -> to_string(value)
    end)
  end

  defp runtime_model(%{agent: %{state: state}}) when is_map(state) do
    Map.get(state, :model) || Map.get(state, "model")
  end

  defp runtime_model(_), do: nil

  defp debug_enabled(opts, raw_state) do
    case Keyword.fetch(opts, :debug_enabled) do
      {:ok, enabled} when is_boolean(enabled) -> enabled
      _ -> raw_state_debug(raw_state)
    end
  end

  defp raw_state_debug(%{debug: enabled}) when is_boolean(enabled), do: enabled
  defp raw_state_debug(_), do: false

  defp debug_label(true), do: "Debug On"
  defp debug_label(false), do: "Debug Off"

  defp debug_variant(true), do: :info
  defp debug_variant(false), do: :default

  defp maybe_meta(_key, nil), do: nil
  defp maybe_meta(key, value), do: {key, to_string(value)}

  defp normalize_timeout(timeout_ms) when is_integer(timeout_ms) and timeout_ms > 0,
    do: timeout_ms

  defp normalize_timeout(_), do: @default_chat_timeout_ms

  defp short_instance_id(id) when is_binary(id) do
    if String.length(id) <= 12, do: id, else: String.slice(id, 0, 12)
  end

  defp short_instance_id(_), do: "instance"

  defp status_label(:running), do: "Running"
  defp status_label(:success), do: "Success"
  defp status_label(:failure), do: "Failure"
  defp status_label(:waiting), do: "Waiting"
  defp status_label(:idle), do: "Idle"
  defp status_label(:available), do: "Available"
  defp status_label(_), do: "Offline"

  defp status_variant(:running), do: :success
  defp status_variant(:success), do: :success
  defp status_variant(:waiting), do: :warning
  defp status_variant(:failure), do: :error
  defp status_variant(:available), do: :default
  defp status_variant(_), do: :default
end
