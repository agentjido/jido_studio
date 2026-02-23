defmodule JidoStudio.Diagnostics.Components do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components

  alias JidoStudio.ScopeQuery

  @spec overview_path(String.t(), String.t() | nil, String.t() | nil) :: String.t()
  def overview_path(prefix, runtime_key, node_param) do
    diagnostics_path(prefix, %{"view" => "overview"}, runtime_key, node_param)
  end

  @spec timeline_path(String.t(), map(), String.t() | nil, String.t() | nil) :: String.t()
  def timeline_path(prefix, filters, runtime_key, node_param) when is_map(filters) do
    diagnostics_path(
      prefix,
      %{
        "view" => "timeline",
        "trace_id" => filters.trace_id,
        "span_id" => filters.span_id,
        "critical" => bool_param(filters.critical),
        "entity_type" => filters.entity_type,
        "hide_internal" => bool_param(filters.hide_internal)
      },
      runtime_key,
      node_param
    )
  end

  attr :prefix, :string, required: true
  attr :runtime_key, :string, default: nil
  attr :cluster_node_param, :string, default: "all"
  attr :node_snapshots, :list, default: []

  def overview_view(assigns) do
    ~H"""
    <div class="grid grid-cols-1 xl:grid-cols-[minmax(0,1.2fr)_minmax(0,0.8fr)] gap-4">
      <.card>
        <h2 class="text-sm font-semibold text-js-text">Cluster Runtime Status</h2>

        <div :if={@node_snapshots == []} class="mt-4">
          <.empty_state
            title="No diagnostics available"
            description="Node diagnostics are unavailable for the current scope."
          />
        </div>

        <div :if={@node_snapshots != []} class="mt-3 divide-y divide-js-border">
          <div :for={snapshot <- @node_snapshots} class="py-2 flex items-start justify-between gap-3">
            <div>
              <div class="text-xs text-js-text font-mono">{snapshot.node}</div>
              <div class="text-[11px] text-js-text-subtle">
                OTP {snapshot.otp_release} | Elixir {snapshot.elixir_version}
              </div>
              <div class="text-[11px] text-js-text-subtle">
                Discovery: {bool_label(snapshot.discovery_loaded)} | Traces: {bool_label(
                  snapshot.tracing_available
                )}
              </div>
            </div>
            <.badge variant={if(snapshot.ok?, do: :success, else: :warning)}>
              {if(snapshot.ok?, do: "reachable", else: "unreachable")}
            </.badge>
          </div>
        </div>
      </.card>

      <.card>
        <h2 class="text-sm font-semibold text-js-text">Deep Tools</h2>
        <div class="mt-3 space-y-2">
          <.link
            navigate={page_path(@prefix, "/traces", @runtime_key, @cluster_node_param)}
            class="block rounded-md border border-js-border px-3 py-2 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
          >
            Traces Explorer
          </.link>
          <.link
            navigate={page_path(@prefix, "/actions", @runtime_key, @cluster_node_param)}
            class="block rounded-md border border-js-border px-3 py-2 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
          >
            Action Diagnostics
          </.link>
          <.link
            navigate={page_path(@prefix, "/workflows", @runtime_key, @cluster_node_param)}
            class="block rounded-md border border-js-border px-3 py-2 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
          >
            Workflow Analysis
          </.link>
          <.link
            navigate={page_path(@prefix, "/signals", @runtime_key, @cluster_node_param)}
            class="block rounded-md border border-js-border px-3 py-2 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
          >
            Signal Stream
          </.link>
          <.link
            navigate={page_path(@prefix, "/threads", @runtime_key, @cluster_node_param)}
            class="block rounded-md border border-js-border px-3 py-2 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
          >
            Threads and Memory
          </.link>
        </div>
      </.card>
    </div>
    """
  end

  attr :prefix, :string, required: true
  attr :runtime_key, :string, default: nil
  attr :cluster_node_param, :string, required: true
  attr :timeline_filters, :map, required: true
  attr :timeline_entity_types, :list, required: true
  attr :timeline_recent_traces, :list, required: true
  attr :timeline_model, :map, default: nil
  attr :timeline_warning, :string, default: nil
  attr :timeline_node_required?, :boolean, required: true

  def timeline_view(assigns) do
    ~H"""
    <div class="space-y-4">
      <.card>
        <div class="flex flex-wrap items-start justify-between gap-3">
          <div>
            <h2 class="text-sm font-semibold text-js-text">Advanced Timeline Waterfall</h2>
            <p class="mt-1 text-xs text-js-text-muted">
              Analyze a single trace with critical-path emphasis, lane grouping, and deep links to diagnostics tools.
            </p>
          </div>
          <.link
            :if={@timeline_filters.trace_id}
            navigate={
              trace_path(
                @prefix,
                @timeline_filters.trace_id,
                @runtime_key,
                @cluster_node_param
              )
            }
            class="inline-flex items-center rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
          >
            Open Standard Trace View
          </.link>
        </div>

        <p :if={@timeline_warning} class="mt-3 text-xs text-js-warning">{@timeline_warning}</p>

        <%= if @timeline_node_required? do %>
          <div class="mt-4">
            <.empty_state
              title="Select a node for timeline"
              description="Timeline view requires a concrete node. Open Advanced Scope in the sidebar and choose a node instead of All Nodes."
            />
          </div>
        <% else %>
          <form
            phx-change="timeline_filters_change"
            class="mt-4 grid grid-cols-1 lg:grid-cols-5 gap-2"
          >
            <label class="text-xs text-js-text-muted lg:col-span-2">
              Trace
              <select
                name="timeline[trace_id]"
                class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
              >
                <option value="">Select trace</option>
                <option
                  :for={trace <- @timeline_recent_traces}
                  value={trace.trace_id}
                  selected={trace.trace_id == @timeline_filters.trace_id}
                >
                  {trace.trace_id} ({trace.status})
                </option>
              </select>
            </label>

            <label class="text-xs text-js-text-muted">
              Lane Filter
              <select
                name="timeline[entity_type]"
                class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
              >
                <option
                  :for={type <- @timeline_entity_types}
                  value={type}
                  selected={type == @timeline_filters.entity_type}
                >
                  {String.capitalize(type)}
                </option>
              </select>
            </label>

            <label class="text-xs text-js-text-muted flex items-end gap-2">
              <input type="hidden" name="timeline[critical]" value="0" />
              <input
                type="checkbox"
                name="timeline[critical]"
                value="1"
                checked={@timeline_filters.critical}
                class="rounded border-js-border bg-js-bg-elevated"
              /> Critical Path Emphasis
            </label>

            <label class="text-xs text-js-text-muted flex items-end gap-2">
              <input type="hidden" name="timeline[hide_internal]" value="0" />
              <input
                type="checkbox"
                name="timeline[hide_internal]"
                value="1"
                checked={@timeline_filters.hide_internal}
                class="rounded border-js-border bg-js-bg-elevated"
              /> Hide Internal
            </label>
          </form>

          <%= if @timeline_recent_traces == [] do %>
            <div class="mt-4">
              <.empty_state
                title="No recent traces"
                description="No traces are available for the selected node in the recent window."
              />
            </div>
          <% else %>
            <%= if is_nil(@timeline_filters.trace_id) do %>
              <div class="mt-4">
                <.empty_state
                  title="Select a trace"
                  description="Choose a trace from the picker to load the timeline waterfall."
                />
              </div>
            <% else %>
              <%= if @timeline_model do %>
                <div class="mt-4 space-y-3">
                  <div class="flex flex-wrap items-center gap-2">
                    <.badge variant={:default}>
                      trace:{@timeline_model.trace_id || "unknown"}
                    </.badge>
                    <.badge variant={:info}>
                      lanes:{length(@timeline_model.lanes)}
                    </.badge>
                    <.badge variant={:default}>
                      spans:{@timeline_model.timed_span_count}/{@timeline_model.total_spans}
                    </.badge>
                    <.badge :if={@timeline_model.truncated?} variant={:warning}>
                      capped at {@timeline_model.span_cap}
                    </.badge>
                  </div>

                  <div
                    :if={@timeline_model.warnings != []}
                    class="rounded-md border border-js-warning/40 bg-js-warning/10 px-3 py-2"
                  >
                    <p
                      :for={warning <- @timeline_model.warnings}
                      class="text-xs text-js-warning"
                    >
                      {warning}
                    </p>
                  </div>

                  <div class="grid grid-cols-1 xl:grid-cols-[220px_minmax(0,1fr)_320px] gap-3">
                    <.card class="p-3">
                      <h3 class="text-xs uppercase tracking-wider text-js-text-subtle mb-2">Lanes</h3>
                      <div class="space-y-1.5 max-h-[36rem] overflow-y-auto js-scroll">
                        <div
                          :for={lane <- @timeline_model.lanes}
                          class="rounded border border-js-border bg-js-bg-elevated/40 px-2 py-1.5"
                        >
                          <div class="text-xs text-js-text truncate">{lane.label}</div>
                          <div class="text-[11px] text-js-text-subtle font-mono">
                            {lane.count} spans
                          </div>
                        </div>
                      </div>
                    </.card>

                    <.card class="p-3 overflow-x-auto">
                      <h3 class="text-xs uppercase tracking-wider text-js-text-subtle mb-2">
                        Waterfall
                      </h3>
                      <%= if @timeline_model.spans == [] do %>
                        <.empty_state
                          title="No timed spans"
                          description="Selected trace has no spans with usable timing data for waterfall rendering."
                        />
                      <% else %>
                        <div class="space-y-1.5 min-w-[640px]">
                          <div
                            :for={lane <- @timeline_model.lanes}
                            class="relative h-11 rounded-md border border-js-border bg-js-bg-elevated/30"
                          >
                            <button
                              :for={span <- lane_spans(@timeline_model.spans, lane.key)}
                              type="button"
                              phx-click="select_timeline_span"
                              phx-value-span_id={span.span_id}
                              class={[
                                "absolute top-1.5 h-8 rounded border px-2 text-left text-[11px] font-mono truncate",
                                if(span.span_id == @timeline_model.selected_span_id,
                                  do: "border-js-info bg-js-info/30 text-js-text",
                                  else:
                                    "border-js-border bg-js-bg-elevated text-js-text-muted hover:text-js-text"
                                ),
                                if(span.critical_path?, do: "ring-1 ring-js-success/60", else: "")
                              ]}
                              style={"left: #{pct(span.left_pct)}%; width: #{pct(span.width_pct)}%;"}
                              title={span.event_name}
                            >
                              {span.event_name}
                            </button>
                          </div>
                        </div>
                      <% end %>
                    </.card>

                    <.card class="p-3">
                      <div class="flex items-center justify-between gap-2">
                        <h3 class="text-xs uppercase tracking-wider text-js-text-subtle">
                          Span Details
                        </h3>
                        <button
                          :if={@timeline_model.selected_span}
                          type="button"
                          phx-click="clear_timeline_span"
                          class="text-[11px] text-js-info hover:text-js-text"
                        >
                          Clear
                        </button>
                      </div>

                      <%= if @timeline_model.selected_span do %>
                        <div class="mt-2 space-y-1.5 text-xs text-js-text-muted">
                          <p class="text-sm text-js-text font-medium">
                            {@timeline_model.selected_span.event_name}
                          </p>
                          <div>
                            <span class="text-js-text-subtle">Span:</span> {@timeline_model.selected_span.span_id}
                          </div>
                          <div>
                            <span class="text-js-text-subtle">Status:</span> {@timeline_model.selected_span.status}
                          </div>
                          <div>
                            <span class="text-js-text-subtle">Offset / Duration:</span>
                            {format_duration(@timeline_model.selected_span.offset_ms)} / {format_duration(
                              @timeline_model.selected_span.duration_ms
                            )}
                          </div>
                          <div>
                            <span class="text-js-text-subtle">Entity:</span>
                            {@timeline_model.selected_span.entity_type} / {@timeline_model.selected_span.entity_id}
                          </div>
                          <div>
                            <span class="text-js-text-subtle">Trace:</span> {@timeline_model.selected_span.trace_id ||
                              @timeline_model.trace_id}
                          </div>
                          <div>
                            <span class="text-js-text-subtle">Call:</span> {@timeline_model.selected_span.call_id ||
                              "-"}
                          </div>
                          <div>
                            <span class="text-js-text-subtle">Task:</span> {@timeline_model.selected_span.task_id ||
                              "-"}
                          </div>
                        </div>

                        <div class="mt-3 space-y-1.5">
                          <.link
                            navigate={
                              trace_path(
                                @prefix,
                                @timeline_model.trace_id,
                                @runtime_key,
                                @cluster_node_param
                              )
                            }
                            class="block rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                          >
                            Open Trace Detail
                          </.link>
                          <.link
                            navigate={
                              deep_link_path(
                                @prefix,
                                "/actions",
                                @timeline_model.trace_id,
                                @timeline_model.selected_span.call_id,
                                @timeline_model.selected_span.task_id,
                                @runtime_key,
                                @cluster_node_param
                              )
                            }
                            class="block rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                          >
                            Open Actions
                          </.link>
                          <.link
                            navigate={
                              deep_link_path(
                                @prefix,
                                "/signals",
                                @timeline_model.trace_id,
                                @timeline_model.selected_span.call_id,
                                @timeline_model.selected_span.task_id,
                                @runtime_key,
                                @cluster_node_param
                              )
                            }
                            class="block rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                          >
                            Open Signals
                          </.link>
                          <.link
                            navigate={
                              deep_link_path(
                                @prefix,
                                "/workflows",
                                @timeline_model.trace_id,
                                @timeline_model.selected_span.call_id,
                                @timeline_model.selected_span.task_id,
                                @runtime_key,
                                @cluster_node_param
                              )
                            }
                            class="block rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
                          >
                            Open Workflows
                          </.link>
                        </div>
                      <% else %>
                        <.empty_state
                          title="No span selected"
                          description="Click a bar in the waterfall to inspect span details and jump to related diagnostics."
                        />
                      <% end %>
                    </.card>
                  </div>
                </div>
              <% else %>
                <div class="mt-4">
                  <.empty_state
                    title="Trace unavailable"
                    description="The selected trace could not be loaded for this node."
                  />
                </div>
              <% end %>
            <% end %>
          <% end %>
        <% end %>
      </.card>
    </div>
    """
  end

  defp diagnostics_path(prefix, params, runtime_key, node_param) do
    query =
      params
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Enum.into(%{})

    base =
      if map_size(query) == 0 do
        prefix <> "/diagnostics"
      else
        prefix <> "/diagnostics?" <> URI.encode_query(query)
      end

    ScopeQuery.with_scope_query(base, runtime_key, node_param)
  end

  defp trace_path(prefix, trace_id, runtime_key, node_param) when is_binary(trace_id) do
    base = prefix <> "/traces/" <> URI.encode_www_form(trace_id)
    ScopeQuery.with_scope_query(base, runtime_key, node_param)
  end

  defp trace_path(prefix, _trace_id, runtime_key, node_param) do
    page_path(prefix, "/traces", runtime_key, node_param)
  end

  defp deep_link_path(prefix, suffix, trace_id, call_id, task_id, runtime_key, node_param) do
    query =
      [trace_id, call_id, task_id]
      |> Enum.reject(&(is_nil(&1) or &1 == ""))
      |> Enum.join(" ")

    base =
      if query == "" do
        prefix <> suffix
      else
        prefix <> suffix <> "?" <> URI.encode_query(%{"query" => query})
      end

    ScopeQuery.with_scope_query(base, runtime_key, node_param)
  end

  defp lane_spans(spans, lane_key) do
    spans
    |> Enum.filter(&(&1.lane_key == lane_key))
    |> Enum.sort_by(&{&1.offset_ms, &1.duration_ms, &1.span_id}, :asc)
  end

  defp pct(value) when is_number(value) do
    :erlang.float_to_binary(value * 1.0, decimals: 3)
  end

  defp pct(_), do: "0.000"

  defp bool_param(true), do: "1"
  defp bool_param(false), do: "0"

  defp bool_label(true), do: "available"
  defp bool_label(false), do: "not available"

  defp page_path(prefix, suffix, runtime_key, node_param) do
    ScopeQuery.with_scope_query(prefix <> suffix, runtime_key, node_param)
  end

  defp format_duration(ms) when is_integer(ms) and ms >= 0, do: "#{ms}ms"
  defp format_duration(_), do: "n/a"
end
