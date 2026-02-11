defmodule JidoStudio.Presenters.ReAct do
  @moduledoc false
  @behaviour JidoStudio.AgentPresenter

  alias JidoStudio.Presenters.Default

  @impl true
  def supports?(_agent_module, strategy_module), do: strategy_module == Jido.AI.Strategies.ReAct

  @impl true
  def static(agent_info) do
    view_model = Default.static(agent_info)

    tabs =
      view_model.tabs
      |> ensure_tab(:reasoning, "Reasoning")
      |> ensure_tab(:context, "Context")

    sections =
      view_model.sections_by_tab
      |> Map.put_new(:reasoning, [
        section("Mode", :badge, "ReAct", variant: :info),
        section(
          "Notes",
          :text,
          "Reasoning metadata appears here when a running instance is selected."
        )
      ])
      |> Map.put_new(:context, [
        section("Context", :text, "Thread and strategy state appear here for running instances.")
      ])

    %{view_model | tabs: tabs, sections_by_tab: sections}
  end

  @impl true
  def runtime(agent_info, nil, _opts), do: static(agent_info)

  def runtime(agent_info, status, opts) do
    view_model = Default.runtime(agent_info, status, opts)
    details = status.snapshot.details || %{}
    raw_state = Map.get(status, :raw_state, %{})
    strategy_state = raw_state[:__strategy__] || %{}
    observability_preview = Keyword.get(opts, :observability_preview, %{})
    recent_events = Map.get(observability_preview, :events, [])

    reasoning_sections = [
      section("Termination", :text, format_optional(details[:termination_reason], "pending")),
      section("Iteration", :text, format_optional(details[:iteration], "0")),
      section("Usage", :kv, usage_rows(details[:usage])),
      section("Tool Calls", :text, Integer.to_string(length(details[:tool_calls] || []))),
      section(
        "Conversation Turns",
        :text,
        Integer.to_string(length(details[:conversation] || []))
      )
    ]

    context_sections =
      [
        section(
          "Thread",
          :kv,
          [
            {"Thread ID", format_optional(thread_id(strategy_state), "n/a")},
            {"Entries", Integer.to_string(thread_entries_count(strategy_state))},
            {"Conversation", Integer.to_string(length(details[:conversation] || []))},
            {"Pending Tool Calls", Integer.to_string(pending_tool_calls_count(strategy_state))},
            {"Thinking Blocks", Integer.to_string(thinking_count(strategy_state))}
          ]
        ),
        section("Recent Events", :kv, event_rows(recent_events)),
        maybe_section("Trace Explorer", Keyword.get(opts, :traces_path)),
        section("Strategy Context", :code, inspect_context(strategy_state))
      ]
      |> Enum.reject(&is_nil/1)

    sections =
      view_model.sections_by_tab
      |> Map.update(:reasoning, reasoning_sections, fn _existing -> reasoning_sections end)
      |> Map.put(:context, context_sections)

    %{view_model | sections_by_tab: sections}
    |> ensure_react_tabs()
  end

  @impl true
  def instance_summary(agent_info, instance, nil, opts) do
    Default.instance_summary(agent_info, instance, nil, opts)
  end

  def instance_summary(agent_info, instance, status, opts) do
    base = Default.instance_summary(agent_info, instance, status, opts)
    details = status.snapshot.details || %{}

    react_meta =
      [
        {"Tool Calls", to_string(length(details[:tool_calls] || []))},
        {"Turns", to_string(length(details[:conversation] || []))}
      ]

    Map.update(base, :meta, react_meta, fn existing -> existing ++ react_meta end)
  end

  @impl true
  def start_form_schema(agent_info), do: Default.start_form_schema(agent_info)

  defp ensure_react_tabs(view_model) do
    tabs =
      view_model.tabs
      |> ensure_tab(:reasoning, "Reasoning")
      |> ensure_tab(:context, "Context")

    %{view_model | tabs: tabs}
  end

  defp ensure_tab(tabs, id, label) do
    if Enum.any?(tabs, &(&1.id == id)), do: tabs, else: tabs ++ [%{id: id, label: label}]
  end

  defp usage_rows(nil), do: []

  defp usage_rows(usage) when is_map(usage) do
    [
      {"Input Tokens", Map.get(usage, :input_tokens)},
      {"Output Tokens", Map.get(usage, :output_tokens)},
      {"Total Tokens", Map.get(usage, :total_tokens)}
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map(fn {k, v} -> {k, to_string(v)} end)
  end

  defp usage_rows(_), do: []

  defp section(title, kind, data, opts \\ []) do
    %{title: title, kind: kind, data: data, variant: Keyword.get(opts, :variant, :default)}
  end

  defp maybe_section(_title, nil), do: nil
  defp maybe_section(title, value), do: section(title, :text, to_string(value))

  defp format_optional(nil, fallback), do: fallback
  defp format_optional(value, _fallback), do: to_string(value)

  defp thread_id(strategy_state) when is_map(strategy_state) do
    strategy_state
    |> Map.get(:thread)
    |> case do
      %{id: id} when is_binary(id) -> id
      _ -> nil
    end
  end

  defp thread_id(_), do: nil

  defp thread_entries_count(strategy_state) when is_map(strategy_state) do
    case Map.get(strategy_state, :thread) do
      %{entries: entries} when is_list(entries) -> length(entries)
      _ -> 0
    end
  end

  defp thread_entries_count(_), do: 0

  defp pending_tool_calls_count(strategy_state) when is_map(strategy_state) do
    strategy_state
    |> Map.get(:pending_tool_calls, [])
    |> List.wrap()
    |> length()
  end

  defp pending_tool_calls_count(_), do: 0

  defp thinking_count(strategy_state) when is_map(strategy_state) do
    strategy_state
    |> Map.get(:thinking_trace, [])
    |> List.wrap()
    |> length()
  end

  defp thinking_count(_), do: 0

  defp event_rows([]), do: [{"Recent", "No events captured yet."}]

  defp event_rows(events) do
    events
    |> Enum.take(10)
    |> Enum.map(fn event ->
      {
        event_time(event[:timestamp_ms]),
        "#{event[:source] || :telemetry} #{event_name(event)}"
      }
    end)
  end

  defp event_name(event) when is_map(event) do
    cond do
      is_binary(event[:event_name]) ->
        event[:event_name]

      is_list(event[:event_prefix]) ->
        Enum.join(event[:event_prefix], ".")

      true ->
        "event"
    end
  end

  defp event_name(_), do: "event"

  defp event_time(ts) when is_integer(ts) do
    ts
    |> DateTime.from_unix!(:millisecond)
    |> Calendar.strftime("%H:%M:%S")
  end

  defp event_time(_), do: "--:--:--"

  defp inspect_context(strategy_state) when is_map(strategy_state) do
    inspect(strategy_state, pretty: true, limit: 120, printable_limit: 20_000)
  end

  defp inspect_context(_), do: "%{}"
end
