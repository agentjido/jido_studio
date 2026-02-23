defmodule JidoStudio.DiagnosticsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Cluster.RPC
  alias JidoStudio.Cluster.Scope
  alias JidoStudio.Diagnostics.Components, as: DiagnosticsComponents
  alias JidoStudio.Diagnostics.Timeline
  alias JidoStudio.GuidedTour
  alias JidoStudio.ProductMetrics
  alias JidoStudio.TraceFilter
  alias JidoStudio.Tracing

  @refresh_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Diagnostics")
      |> assign(:node_snapshots, [])
      |> assign(:diagnostic_warning, nil)
      |> assign(:view, "overview")
      |> assign(:timeline_filters, default_timeline_filters())
      |> assign(:timeline_entity_types, Timeline.entity_types())
      |> assign(:timeline_recent_traces, [])
      |> assign(:timeline_model, nil)
      |> assign(:timeline_warning, nil)
      |> assign(:timeline_node_required?, false)

    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    view = normalize_view(params["view"])

    socket =
      socket
      |> assign(:view, view)
      |> assign(:timeline_filters, parse_timeline_filters(params))
      |> refresh_diagnostics()

    {:noreply, socket}
  end

  @impl true
  def handle_event("timeline_filters_change", %{"timeline" => params}, socket) do
    current = socket.assigns.timeline_filters

    updated =
      current
      |> Map.merge(parse_timeline_form(params))
      |> maybe_clear_selected_span(current, params)

    {:noreply,
     push_patch(socket,
       to:
         DiagnosticsComponents.timeline_path(
           socket.assigns.prefix,
           updated,
           socket.assigns.runtime_key,
           socket.assigns.cluster_node_param
         )
     )}
  end

  @impl true
  def handle_event("select_timeline_span", %{"span_id" => span_id}, socket) do
    normalized_span_id = normalize_optional_string(span_id)

    :ok =
      ProductMetrics.triage_root_cause_opened(socket,
        source: "diagnostics_timeline",
        trace_id: socket.assigns.timeline_filters.trace_id,
        span_id: normalized_span_id
      )

    filters =
      socket.assigns.timeline_filters
      |> Map.put(:span_id, normalized_span_id)

    {:noreply,
     push_patch(socket,
       to:
         DiagnosticsComponents.timeline_path(
           socket.assigns.prefix,
           filters,
           socket.assigns.runtime_key,
           socket.assigns.cluster_node_param
         )
     )}
  end

  @impl true
  def handle_event("clear_timeline_span", _params, socket) do
    filters = Map.put(socket.assigns.timeline_filters, :span_id, nil)

    {:noreply,
     push_patch(socket,
       to:
         DiagnosticsComponents.timeline_path(
           socket.assigns.prefix,
           filters,
           socket.assigns.runtime_key,
           socket.assigns.cluster_node_param
         )
     )}
  end

  @impl true
  def handle_event("tour_metric", params, socket) do
    {:noreply, GuidedTour.track_metric(socket, params)}
  end

  @impl true
  def handle_info(:refresh, socket) do
    {:noreply, refresh_diagnostics(socket)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header
        title="Diagnostics"
        subtitle="Why did this fail in the selected runtime and node?"
      >
        <:actions>
          <div class="inline-flex rounded-md border border-js-border bg-js-bg-elevated p-1">
            <.link
              patch={
                DiagnosticsComponents.overview_path(
                  @prefix,
                  @runtime_key,
                  @cluster_node_param
                )
              }
              class={[
                "rounded px-2.5 py-1 text-xs transition-colors",
                if(@view == "overview",
                  do: "bg-js-muted text-js-text",
                  else: "text-js-text-muted hover:text-js-text"
                )
              ]}
            >
              Overview
            </.link>
            <.link
              patch={
                DiagnosticsComponents.timeline_path(
                  @prefix,
                  @timeline_filters,
                  @runtime_key,
                  @cluster_node_param
                )
              }
              data-tour-id="diagnostics-timeline-toggle"
              class={[
                "rounded px-2.5 py-1 text-xs transition-colors",
                if(@view == "timeline",
                  do: "bg-js-muted text-js-text",
                  else: "text-js-text-muted hover:text-js-text"
                )
              ]}
            >
              Timeline (Advanced)
            </.link>
          </div>
          <.badge variant={:default}>runtime:{@runtime_key || "default"}</.badge>
          <.badge variant={:info}>node:{@cluster_node_param || "all"}</.badge>
        </:actions>
      </.page_header>

      <.tour_metric_bridge />

      <.card class="py-3">
        <p class="text-xs text-js-text-muted">
          What this page is for: validate cluster connectivity, runtime health, and jump into deep investigation tools.
        </p>
        <p :if={@diagnostic_warning} class="mt-2 text-xs text-js-warning">{@diagnostic_warning}</p>
      </.card>

      <%= if @view == "timeline" do %>
        <DiagnosticsComponents.timeline_view
          prefix={@prefix}
          runtime_key={@runtime_key}
          cluster_node_param={@cluster_node_param}
          timeline_filters={@timeline_filters}
          timeline_entity_types={@timeline_entity_types}
          timeline_recent_traces={@timeline_recent_traces}
          timeline_model={@timeline_model}
          timeline_warning={@timeline_warning}
          timeline_node_required?={@timeline_node_required?}
        />
      <% else %>
        <DiagnosticsComponents.overview_view
          prefix={@prefix}
          runtime_key={@runtime_key}
          cluster_node_param={@cluster_node_param}
          node_snapshots={@node_snapshots}
        />
      <% end %>
    </div>
    """
  end

  @doc false
  def node_snapshot_local do
    %{
      node: to_string(Node.self()),
      otp_release: to_string(:erlang.system_info(:otp_release)),
      elixir_version: System.version(),
      discovery_loaded: Code.ensure_loaded?(Jido.Discovery),
      tracing_available: Code.ensure_loaded?(JidoStudio.Tracing),
      ok?: true
    }
  rescue
    _ ->
      %{
        node: to_string(Node.self()),
        otp_release: "unknown",
        elixir_version: "unknown",
        discovery_loaded: false,
        tracing_available: false,
        ok?: false
      }
  end

  defp refresh_diagnostics(socket) do
    socket
    |> refresh_node_snapshots()
    |> maybe_refresh_timeline()
  end

  defp refresh_node_snapshots(socket) do
    scope = socket.assigns.cluster_scope

    snapshots =
      case RPC.call(scope, __MODULE__, :node_snapshot_local, []) do
        {:ok, results} when is_list(results) ->
          Enum.map(results, fn
            %{ok?: true, value: value, node: node} when is_map(value) ->
              value
              |> Map.put_new(:node, to_string(node))
              |> Map.put(:ok?, true)

            %{node: node, error: _error} ->
              %{
                node: to_string(node),
                ok?: false,
                otp_release: "-",
                elixir_version: "-",
                discovery_loaded: false,
                tracing_available: false
              }
          end)

        {:ok, snapshot} when is_map(snapshot) ->
          [Map.put(snapshot, :ok?, true)]

        {:error, _reason} ->
          []
      end

    warning =
      if Enum.any?(snapshots, &(&1.ok? == false)) do
        "One or more nodes are unreachable or degraded for RPC diagnostics."
      else
        nil
      end

    socket
    |> assign(:node_snapshots, Enum.sort_by(snapshots, &to_string(&1.node)))
    |> assign(:diagnostic_warning, warning)
  end

  defp maybe_refresh_timeline(%{assigns: %{view: "timeline"}} = socket) do
    selected_node = Scope.selected_node(socket.assigns.cluster_scope)

    if is_nil(selected_node) do
      socket
      |> assign(:timeline_node_required?, true)
      |> assign(:timeline_recent_traces, [])
      |> assign(:timeline_model, nil)
      |> assign(
        :timeline_warning,
        "Timeline requires a concrete node. Open Advanced Scope and select a node."
      )
    else
      refresh_timeline_for_node(socket, selected_node)
    end
  end

  defp maybe_refresh_timeline(socket) do
    socket
    |> assign(:timeline_node_required?, false)
    |> assign(:timeline_recent_traces, [])
    |> assign(:timeline_model, nil)
    |> assign(:timeline_warning, nil)
  end

  defp refresh_timeline_for_node(socket, node) do
    scope = {:node, node}
    filters = socket.assigns.timeline_filters

    recent_traces = Timeline.pick_recent_traces(scope, limit: 50, range: "1h")
    trace_id = filters.trace_id

    socket =
      socket
      |> assign(:timeline_node_required?, false)
      |> assign(:timeline_recent_traces, recent_traces)

    if is_nil(trace_id) do
      socket
      |> assign(:timeline_model, nil)
      |> assign(:timeline_warning, nil)
    else
      span_cap = timeline_span_cap()
      entity_filter = if(filters.entity_type in [nil, "all"], do: nil, else: filters.entity_type)
      span_filters = %{hide_internal: filters.hide_internal, entity_type: entity_filter}

      with {:ok, trace} <- fetch_trace(scope, trace_id),
           {:ok, spans} when is_list(spans) <-
             RPC.call(scope, Tracing, :list_trace_spans, [
               trace_id,
               [limit: span_cap, filters: span_filters]
             ]) do
        model =
          Timeline.build(trace, spans,
            selected_span_id: filters.span_id,
            critical: filters.critical,
            span_cap: span_cap
          )

        socket
        |> assign(:timeline_model, model)
        |> assign(:timeline_warning, nil)
      else
        {:error, reason} ->
          socket
          |> assign(:timeline_model, nil)
          |> assign(:timeline_warning, timeline_error_message(reason))

        _ ->
          socket
          |> assign(:timeline_model, nil)
          |> assign(:timeline_warning, "Selected trace is unavailable on this node.")
      end
    end
  end

  defp timeline_error_message(%{kind: :nodedown}) do
    "Selected node is unreachable for timeline RPC calls."
  end

  defp timeline_error_message(%{kind: :timeout}) do
    "Timeline RPC timed out for selected node."
  end

  defp timeline_error_message(:not_found) do
    "Selected trace is unavailable on this node."
  end

  defp timeline_error_message(_reason) do
    "Timeline data is unavailable for the selected node."
  end

  defp fetch_trace(scope, trace_id) do
    case RPC.call(scope, Tracing, :get_trace, [trace_id]) do
      {:ok, {:ok, trace}} when is_map(trace) -> {:ok, trace}
      {:ok, :not_found} -> {:error, :not_found}
      {:ok, {:error, reason}} -> {:error, reason}
      {:error, reason} -> {:error, reason}
      _ -> {:error, :not_found}
    end
  end

  defp default_timeline_filters do
    %{
      trace_id: nil,
      span_id: nil,
      critical: true,
      entity_type: "all",
      hide_internal: TraceFilter.hide_internal_default?()
    }
  end

  defp parse_timeline_filters(params) when is_map(params) do
    %{
      trace_id: normalize_optional_string(params["trace_id"]),
      span_id: normalize_optional_string(params["span_id"]),
      critical: parse_boolean(params["critical"], true),
      entity_type: normalize_entity_type(params["entity_type"]),
      hide_internal: parse_boolean(params["hide_internal"], TraceFilter.hide_internal_default?())
    }
  end

  defp parse_timeline_filters(_), do: default_timeline_filters()

  defp parse_timeline_form(params) when is_map(params) do
    %{
      trace_id: normalize_optional_string(params["trace_id"]),
      critical: parse_boolean(params["critical"], true),
      entity_type: normalize_entity_type(params["entity_type"]),
      hide_internal: parse_boolean(params["hide_internal"], TraceFilter.hide_internal_default?())
    }
  end

  defp parse_timeline_form(_), do: %{}

  defp maybe_clear_selected_span(updated, current, params) do
    trace_from_form = normalize_optional_string(params["trace_id"])

    if trace_from_form != current.trace_id do
      Map.put(updated, :span_id, nil)
    else
      Map.put(updated, :span_id, current.span_id)
    end
  end

  defp normalize_view("timeline"), do: "timeline"
  defp normalize_view(_), do: "overview"

  defp normalize_entity_type(value) when is_binary(value) do
    normalized = String.downcase(String.trim(value))
    if normalized in Timeline.entity_types(), do: normalized, else: "all"
  end

  defp normalize_entity_type(_), do: "all"

  defp parse_boolean(nil, default), do: default
  defp parse_boolean(value, _default) when value in [true, "true", "1", 1], do: true
  defp parse_boolean(value, _default) when value in [false, "false", "0", 0], do: false
  defp parse_boolean(_value, default), do: default

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(_), do: nil

  defp timeline_span_cap do
    min(TraceFilter.max_span_rows(), 2_000)
  end
end
