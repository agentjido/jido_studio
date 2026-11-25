defmodule JidoStudio.Live.AgentsLive.Render.BasicInstanceView do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components
  import JidoStudio.Live.AgentsLive.Support

  alias JidoStudio.Agents.RunnerForm
  alias JidoStudio.Live.AgentsLive.ShowState

  @state_preview_limit 8
  @state_value_limit 140

  def show(assigns) do
    state = current_state(assigns.runtime_status)

    assigns =
      assigns
      |> assign(:next_actions, next_actions(assigns))
      |> assign(:selected_operation, selected_operation(assigns))
      |> assign(:current_state, state)
      |> assign(:state_rows, state_rows(state))
      |> assign(:state_json, state_json(state))

    ~H"""
    <div
      class="p-3 lg:p-4 lg:flex-1 lg:min-h-0 lg:overflow-hidden lg:flex lg:flex-col"
      id="agent-workbench"
    >
      <div class="js-agent-topbar flex items-center justify-between gap-3 shrink-0 mb-3">
        <div class="flex items-center gap-2 text-sm text-js-text-muted">
          <.link navigate={scoped_path(@prefix <> "/agents")} class="hover:text-js-text">
            Agents
          </.link>
          <span>/</span>
          <.link navigate={@module_path} class="hover:text-js-text">
            {humanize_agent_name(@agent.name)}
          </.link>
          <span :if={@active_instance_id}>
            / <span class="text-js-text-subtle">{short_instance_id(@active_instance_id)}</span>
          </span>
          <.badge :if={not @instance_online?} variant={:default}>
            Instance Offline
          </.badge>
        </div>

        <div class="flex items-center gap-2">
          <div class="inline-flex items-center rounded-md border border-js-border bg-js-bg-elevated/20 p-0.5">
            <.link
              patch={@basic_view_path}
              class="rounded bg-js-bg-elevated px-2 py-1 text-xs text-js-text"
            >
              Basic View
            </.link>
            <.link
              patch={@advanced_view_path}
              class="rounded px-2 py-1 text-xs text-js-text-muted hover:text-js-text"
            >
              Advanced View
            </.link>
          </div>
          <.link
            navigate={@traces_path}
            class="inline-flex items-center gap-2 rounded-md border border-js-border px-3 py-1.5 text-sm text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated transition-colors"
          >
            <Lucideicons.activity class="w-4 h-4" /> Traces
          </.link>
        </div>
      </div>

      <div class="flex-1 min-h-0 overflow-y-auto space-y-3">
        <.card class="py-3">
          <div class="px-4 lg:px-5">
            <h2 class="text-sm font-semibold text-js-text">Simple Agent Loop</h2>
            <p class="text-xs text-js-text-muted mt-1">
              Pick one starter operation, enter inputs, confirm, run once, then review what changed.
            </p>
          </div>
        </.card>

        <div class="grid gap-3 lg:grid-cols-2 lg:min-h-0">
          <.card class="space-y-3 lg:min-h-0 lg:flex lg:flex-col border-js-info/30">
            <div>
              <h3 class="text-sm font-semibold text-js-text">1. Pick a Starter Operation</h3>
              <p class="text-xs text-js-text-muted mt-1">
                `Ping` checks health, `Add` sums numbers, `Tip` calculates a bill, and `Reset` returns defaults.
              </p>
            </div>

            <%= if @starter_operations == [] do %>
              <.empty_state
                title="No starter operations available"
                description="Open Advanced View to inspect routes and choose a signal/action manually."
              />
            <% else %>
              <div class="space-y-2 lg:overflow-y-auto lg:pr-1">
                <button
                  :for={operation <- @starter_operations}
                  type="button"
                  phx-click="prefill_starter_operation"
                  phx-value-id={operation.id}
                  class={[
                    "w-full text-left rounded-md border px-3 py-3 transition-colors",
                    if(
                      @selected_runner_target == {:signal, operation.selection_key} or
                        @selected_runner_target == {:action, operation.selection_key},
                      do: "border-js-info/60 bg-js-info/10",
                      else: "border-js-border hover:bg-js-bg-elevated"
                    )
                  ]}
                >
                  <div class="flex items-center justify-between gap-2">
                    <span class="text-sm font-medium text-js-text">
                      {operation_display_label(operation)}
                    </span>
                    <span class="text-[11px] font-mono text-js-text-subtle">
                      {operation.signal_type}
                    </span>
                  </div>
                  <p class="mt-1 text-xs text-js-text-muted">{operation.rationale}</p>
                </button>
              </div>
            <% end %>
          </.card>

          <.card class="space-y-3 lg:min-h-0 lg:flex lg:flex-col">
            <div>
              <h3 class="text-sm font-semibold text-js-text">2. Set Inputs and Run</h3>
              <p class="text-xs text-js-text-muted mt-1">
                Selected operation:
                <span class="text-js-text font-medium">
                  {selected_operation_label(@selected_operation, @selected_runner_target)}
                </span>
              </p>
              <p
                :if={
                  is_binary(selected_operation_signal(@selected_operation, @selected_runner_target))
                }
                class="text-xs text-js-text-subtle mt-1"
              >
                Signal sent:
                <span class="font-mono">
                  {selected_operation_signal(@selected_operation, @selected_runner_target)}
                </span>
              </p>
              <p
                :if={is_map(@selected_operation)}
                class="text-xs text-js-text-subtle mt-1"
              >
                {@selected_operation.rationale}
              </p>
              <button
                :if={is_map(@selected_operation)}
                type="button"
                phx-click="prefill_starter_operation"
                phx-value-id={@selected_operation.id}
                class="mt-2 inline-flex rounded-md border border-js-info/40 bg-js-info/10 px-2.5 py-1 text-xs text-js-info hover:brightness-110"
              >
                Use Sample Inputs
              </button>
            </div>

            <div class="grid gap-3 xl:grid-cols-2 xl:min-h-0">
              <div class="space-y-3 rounded-md border border-js-info/30 bg-js-info/5 p-3">
                <div class="rounded-md border border-js-info/40 bg-js-info/10 px-3 py-2.5 text-xs text-js-text-muted">
                  Input Editor
                  <div class="mt-1 inline-flex rounded-md border border-js-info/40 bg-js-bg p-0.5">
                    <button
                      type="button"
                      phx-click="set_schema_mode"
                      phx-value-mode="fields"
                      class={schema_mode_button_class(@runner_form.schema_mode == "fields")}
                    >
                      Guided Fields
                    </button>
                    <button
                      type="button"
                      phx-click="set_schema_mode"
                      phx-value-mode="raw"
                      class={schema_mode_button_class(@runner_form.schema_mode == "raw")}
                    >
                      Raw JSON (Advanced)
                    </button>
                  </div>
                  <p class="mt-1 text-[11px] text-js-text-subtle">
                    Use Guided Fields unless this operation needs custom nested JSON.
                  </p>
                </div>

                <%= if @runner_form.schema_mode == "fields" and @payload_form.supported? do %>
                  <form phx-change="update_runner_fields" class="space-y-2">
                    <div class="grid gap-2 sm:grid-cols-2">
                      <label
                        :for={field <- @payload_form.fields}
                        class="block rounded-md border border-js-info/35 bg-js-bg p-2.5 text-xs text-js-text-muted"
                      >
                        <div class="flex items-center justify-between gap-2">
                          <span class="font-medium text-js-text">{field.label}</span>
                          <span class="rounded border border-js-border px-1.5 py-0.5 text-[10px] uppercase tracking-wide text-js-text-subtle">
                            {field_type_label(field.type)}
                          </span>
                        </div>
                        <p
                          :if={show_field_description?(field.description)}
                          class="mt-1 text-[11px] text-js-text-subtle"
                        >
                          {field_description(field.description)}
                        </p>
                        <input
                          type={field_input_type(field.type)}
                          inputmode={field_input_mode(field.type)}
                          step={field_input_step(field.type)}
                          name={"fields[#{field.name}]"}
                          value={field.value}
                          placeholder={field_placeholder(field)}
                          class="mt-2 w-full rounded-md border border-js-info/35 bg-js-bg-surface px-2.5 py-2 text-sm text-js-text font-mono"
                        />
                        <p :if={field.required?} class="mt-1 text-[11px] text-js-text-subtle">
                          Required
                        </p>
                        <p :if={field.error} class="mt-1 text-[11px] text-js-error">{field.error}</p>
                      </label>
                    </div>
                  </form>
                <% else %>
                  <div class="space-y-2">
                    <p
                      :if={@runner_form.schema_mode == "fields" and is_binary(@payload_form.reason)}
                      class="rounded-md border border-js-warning/40 bg-js-warning/10 px-2.5 py-2 text-xs text-js-warning"
                    >
                      {payload_form_message(@payload_form.reason)}
                    </p>
                    <form phx-change="update_runner_payload" class="space-y-2">
                      <input
                        type="hidden"
                        name="runner[schema_mode]"
                        value={@runner_form.schema_mode}
                      />
                      <label class="text-xs text-js-text-muted block">
                        Payload JSON <textarea
                          name="runner[payload_json]"
                          rows="8"
                          class="mt-1 w-full rounded-md border border-js-border bg-js-bg p-2.5 text-xs text-js-text font-mono"
                        ><%= @runner_form.payload_json %></textarea>
                      </label>
                    </form>
                  </div>
                <% end %>

                <details class="rounded-md border border-js-info/30 bg-js-bg-elevated/20 px-2.5 py-2 text-xs text-js-text-muted">
                  <summary class="cursor-pointer text-js-text-muted">Advanced: Dispatch mode</summary>
                  <label class="block mt-2">
                    <select
                      name="mode"
                      phx-change="set_dispatch_mode"
                      class="w-full rounded-md border border-js-border bg-js-bg px-2.5 py-2 text-xs text-js-text"
                    >
                      <option value="sync" selected={@runner_form.dispatch_mode == "sync"}>
                        sync (wait for result)
                      </option>
                      <option value="async" selected={@runner_form.dispatch_mode == "async"}>
                        async (queue only)
                      </option>
                    </select>
                  </label>
                </details>

                <div class="rounded-md border border-js-warning/45 bg-js-warning/10 p-2.5 space-y-2">
                  <p class="text-xs text-js-text-muted">
                    Safety check: confirm inputs before dispatching.
                  </p>
                  <div class="flex flex-wrap items-center gap-2">
                    <div class="mt-1 inline-flex rounded-md border border-js-warning/40 bg-js-bg p-0.5">
                      <button
                        type="button"
                        phx-click="arm_runner_execute"
                        class={
                          if(@runner_form.guard_armed?,
                            do:
                              "inline-flex rounded-md border border-js-success/40 bg-js-success/10 px-3 py-1.5 text-xs text-js-success",
                            else:
                              "inline-flex rounded-md border border-js-info/40 bg-js-info/10 px-3 py-1.5 text-xs text-js-info hover:brightness-110"
                          )
                        }
                      >
                        {if(@runner_form.guard_armed?, do: "Inputs Confirmed", else: "Confirm Inputs")}
                      </button>
                      <button
                        type="button"
                        phx-click="run_selected_interaction"
                        disabled={!RunnerForm.can_execute?(@runner_form)}
                        class={[
                          "inline-flex rounded-md px-3 py-1.5 text-xs disabled:opacity-50 disabled:cursor-not-allowed",
                          if(RunnerForm.can_execute?(@runner_form),
                            do:
                              "border border-js-success/45 bg-js-success/10 text-js-success hover:brightness-110",
                            else: "border border-js-border text-js-text-muted"
                          )
                        ]}
                      >
                        Run Interaction
                      </button>
                      <button
                        type="button"
                        phx-click="clear_runner_history"
                        class="inline-flex rounded-md border border-js-border px-3 py-1.5 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                      >
                        Clear History
                      </button>
                    </div>
                  </div>
                  <p class="text-[11px] text-js-text-subtle">
                    {runner_guard_hint(@runner_form.guard_armed?)}
                  </p>
                </div>
              </div>

              <div class="rounded-md border border-js-success/35 bg-js-success/5 p-3 space-y-2 xl:min-h-full">
                <div>
                  <h4 class="text-sm font-semibold text-js-text">Current Agent State</h4>
                  <p class="text-xs text-js-text-muted mt-1">
                    Live snapshot from this instance. Run an operation, then watch these values update.
                  </p>
                </div>
                <%= if @state_rows == [] do %>
                  <p class="text-xs text-js-text-muted">
                    No readable top-level state fields were found.
                  </p>
                <% else %>
                  <dl class="grid gap-1.5">
                    <div
                      :for={row <- @state_rows}
                      class="flex items-start justify-between gap-3 text-xs rounded-md border border-js-success/25 bg-js-bg/70 px-2 py-1.5"
                    >
                      <dt class="font-mono text-js-text">{row.key}</dt>
                      <dd class="font-mono text-js-text text-right break-all">{row.value}</dd>
                    </div>
                  </dl>
                <% end %>
                <details class="rounded-md border border-js-success/30 bg-js-bg px-2.5 py-2">
                  <summary class="cursor-pointer text-xs text-js-text-muted">
                    View raw state JSON
                  </summary>
                  <pre class="mt-2 text-[11px] text-js-text-subtle whitespace-pre-wrap break-words"><%= @state_json %></pre>
                </details>
              </div>
            </div>
          </.card>
        </div>

        <.card class="space-y-3">
          <h3 class="text-sm font-semibold text-js-text">3. See What Happened</h3>
          <%= if is_nil(@last_run_summary) do %>
            <p class="text-xs text-js-text-muted">
              Run once to see status, state changes, and suggested next steps.
            </p>
          <% else %>
            <div class="flex items-center gap-2">
              <.badge variant={if(@last_run_summary.status == :success, do: :success, else: :error)}>
                {if(@last_run_summary.status == :success, do: "Run Succeeded", else: "Run Failed")}
              </.badge>
              <span class="text-xs font-mono text-js-text-subtle">
                {@last_run_summary.signal_type}
              </span>
            </div>
            <p :if={@last_run_summary.status == :error} class="text-xs text-js-error">
              Error: {@last_run_summary[:error] || "unknown"}
            </p>

            <%= if @last_run_summary.status == :success do %>
              <p class="text-xs text-js-text-muted">
                {@last_run_summary.memory_note}
              </p>

              <%= if @last_run_summary.state_changed? do %>
                <button
                  type="button"
                  phx-click="toggle_state_delta"
                  class="inline-flex rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text"
                >
                  {if(@show_state_delta?, do: "Hide what changed", else: "Show what changed")}
                </button>

                <div :if={@show_state_delta?} class="space-y-1">
                  <div
                    :for={entry <- @last_run_summary.state_delta}
                    class="rounded border border-js-border bg-js-bg-elevated/30 px-2.5 py-2 text-xs"
                  >
                    <p class="font-mono text-js-text">{entry.key}</p>
                    <p class="text-js-text-muted mt-1">Before: {entry.previous}</p>
                    <p class="text-js-text-muted">After: {entry.current}</p>
                  </div>
                </div>
              <% else %>
                <p class="text-xs text-js-text-muted">No state fields changed in this run.</p>
              <% end %>
            <% else %>
              <p class="text-xs text-js-text-muted">Fix the inputs above, then run again.</p>
            <% end %>

            <div class="flex flex-wrap items-center gap-2 pt-1">
              <button
                :for={action <- @next_actions}
                type="button"
                phx-click="open_next_action"
                phx-value-path={action.path}
                phx-value-next_action={action.key}
                phx-value-trace_id={@last_run_summary.trace_id || ""}
                class="inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
              >
                {action.label}
              </button>
            </div>
          <% end %>
        </.card>
      </div>
    </div>
    """
  end

  defp selected_operation(%{starter_operations: operations, selected_runner_target: target})
       when is_list(operations) do
    case target do
      {:signal, key} ->
        Enum.find(operations, &(&1.selection_kind == :signal and &1.selection_key == key))

      {:action, key} ->
        Enum.find(operations, &(&1.selection_kind == :action and &1.selection_key == key))

      _ ->
        nil
    end
  end

  defp selected_operation(_), do: nil

  defp operation_display_label(%{label: label, signal_type: signal_type})
       when is_binary(label) and is_binary(signal_type) do
    case signal_type do
      "beginner.ping" -> "Ping (check instance health)"
      "beginner.add" -> "Add (sum two numbers)"
      "beginner.tip" -> "Tip (calculate tip + total)"
      "beginner.reset" -> "Reset (restore default state)"
      _ -> label
    end
  end

  defp operation_display_label(%{label: label}) when is_binary(label), do: label
  defp operation_display_label(_), do: "Starter operation"

  defp selected_operation_label(%{signal_type: signal_type} = operation, _target)
       when is_binary(signal_type),
       do: operation_display_label(operation)

  defp selected_operation_label(_, {:signal, key}) when is_binary(key),
    do: "Signal #{compact_signal_key(key)}"

  defp selected_operation_label(_, {:action, key}) when is_binary(key),
    do: "Action #{compact_signal_key(key)}"

  defp selected_operation_label(_, _), do: "No operation selected yet"

  defp selected_operation_signal(%{signal_type: signal_type}, _target)
       when is_binary(signal_type),
       do: signal_type

  defp selected_operation_signal(_, {:signal, key}) when is_binary(key),
    do: compact_signal_key(key)

  defp selected_operation_signal(_, _), do: nil

  defp payload_form_message(reason) when is_binary(reason) do
    "Guided fields unavailable: #{reason} Switch to Raw JSON (Advanced) to continue."
  end

  defp schema_mode_button_class(true),
    do: "rounded bg-js-bg-elevated px-2.5 py-1.5 text-xs text-js-text"

  defp schema_mode_button_class(false),
    do: "rounded px-2.5 py-1.5 text-xs text-js-text-muted hover:text-js-text"

  defp field_type_label(type) when type in [:string, :number, :integer, :boolean],
    do: Atom.to_string(type)

  defp field_type_label(_), do: "value"

  defp field_input_type(:number), do: "number"
  defp field_input_type(:integer), do: "number"
  defp field_input_type(_), do: "text"

  defp field_input_mode(:number), do: "decimal"
  defp field_input_mode(:integer), do: "numeric"
  defp field_input_mode(_), do: "text"

  defp field_input_step(:number), do: "any"
  defp field_input_step(:integer), do: "1"
  defp field_input_step(_), do: nil

  defp field_placeholder(%{type: :string}), do: "text"
  defp field_placeholder(%{type: :integer}), do: "whole number"
  defp field_placeholder(%{type: :number}), do: "number"
  defp field_placeholder(%{type: :boolean}), do: "true or false"
  defp field_placeholder(_), do: "value"

  defp show_field_description?(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.trim_trailing(".")

    normalized != "" and String.downcase(normalized) != "no description provided"
  end

  defp show_field_description?(_), do: false

  defp field_description(value) when is_binary(value), do: String.trim(value)

  defp runner_guard_hint(true),
    do: "Inputs are confirmed. Any edit will require confirmation again."

  defp runner_guard_hint(false),
    do: "Review inputs, then click Confirm Inputs before running."

  defp next_actions(assigns) do
    base_actions = [
      %{
        key: "instance_events",
        label: "Open Events",
        path:
          workbench_path(
            assigns.prefix,
            assigns.agent,
            assigns.active_instance_id,
            :events,
            assigns.detail_tab,
            :observe,
            :advanced
          )
      },
      %{
        key: "thread_context",
        label: "Open Thread Context",
        path:
          workbench_path(
            assigns.prefix,
            assigns.agent,
            assigns.active_instance_id,
            :thread_context,
            assigns.detail_tab,
            :observe,
            :advanced
          )
      }
    ]

    trace_actions =
      if is_binary(get_in(assigns, [:last_run_summary, :trace_id])) do
        trace_id = assigns.last_run_summary.trace_id

        [
          %{
            key: "trace",
            label: "Open Trace",
            path: append_query(assigns.traces_path, %{"trace_id" => trace_id})
          },
          %{
            key: "diagnostics_timeline",
            label: "Open Diagnostics Timeline",
            path:
              scoped_path(
                assigns.prefix <>
                  "/diagnostics?" <>
                  URI.encode_query(%{
                    "trace_id" => trace_id,
                    "agent_id" => assigns.active_instance_id
                  })
              )
          }
        ]
      else
        []
      end

    base_actions ++ trace_actions
  end

  defp append_query(path, params) when is_binary(path) and is_map(params) do
    uri = URI.parse(path)
    existing = if is_binary(uri.query), do: URI.decode_query(uri.query), else: %{}
    query = existing |> Map.merge(params) |> URI.encode_query()
    uri |> Map.put(:query, query) |> URI.to_string()
  end

  defp current_state(%{raw_state: raw_state}) when is_map(raw_state) do
    raw_state
    |> from_struct_if_needed()
    |> Enum.reduce(%{}, fn {key, value}, acc ->
      normalized_key = to_string(key)

      if String.starts_with?(normalized_key, "__") do
        acc
      else
        Map.put(acc, normalized_key, value)
      end
    end)
  end

  defp current_state(_), do: %{}

  defp from_struct_if_needed(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp from_struct_if_needed(value), do: value

  defp state_rows(state) when is_map(state) do
    state
    |> Enum.sort_by(fn {key, _value} -> String.downcase(key) end)
    |> Enum.take(@state_preview_limit)
    |> Enum.map(fn {key, value} ->
      %{key: key, value: summarize_state_value(value)}
    end)
  end

  defp state_rows(_), do: []

  defp state_json(state) when state == %{}, do: "{}"

  defp state_json(state) when is_map(state) do
    case Jason.encode(state, pretty: true) do
      {:ok, encoded} ->
        encoded

      _ ->
        inspect(state, pretty: true, limit: 80, printable_limit: 20_000)
    end
  end

  defp state_json(_), do: "{}"

  defp summarize_state_value(value) do
    value
    |> state_value_string()
    |> truncate_state_value()
  end

  defp truncate_state_value(value)
       when is_binary(value) and byte_size(value) > @state_value_limit do
    String.slice(value, 0, @state_value_limit) <> "..."
  end

  defp truncate_state_value(value), do: value

  defp state_value_string(value) when is_binary(value) do
    case maybe_decode_wrapped_json_string(value) do
      {:ok, decoded} -> decoded
      :error -> value
    end
  end

  defp state_value_string(value),
    do: inspect(value, limit: 20, printable_limit: 1_500, pretty: false)

  defp maybe_decode_wrapped_json_string(value) when is_binary(value) do
    normalized = String.trim(value)

    if String.starts_with?(normalized, "\"") and String.ends_with?(normalized, "\"") do
      case Jason.decode(normalized) do
        {:ok, decoded} when is_binary(decoded) -> {:ok, decoded}
        _ -> :error
      end
    else
      :error
    end
  end

  defp compact_signal_key(key) when is_binary(key) do
    key
    |> String.split("::", parts: 2)
    |> List.first()
  end

  defp scoped_path(path), do: ShowState.scoped_path(path)
end
