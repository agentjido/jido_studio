defmodule JidoStudio.DiagnosticsLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Cluster.RPC
  alias JidoStudio.ScopeQuery

  @refresh_ms 5_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(@refresh_ms, self(), :refresh)

    socket =
      socket
      |> assign(:page_title, "Diagnostics")
      |> assign(:node_snapshots, [])
      |> assign(:diagnostic_warning, nil)

    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _uri, socket) do
    {:noreply, refresh_diagnostics(socket)}
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
        subtitle="Technical tools for debugging agents and runtime behavior"
      >
        <:actions>
          <.badge variant={:default}>runtime:{@runtime_key || "default"}</.badge>
          <.badge variant={:info}>node:{@cluster_node_param || "all"}</.badge>
        </:actions>
      </.page_header>

      <.card class="py-3">
        <p class="text-xs text-js-text-muted">
          What this page is for: validate cluster connectivity, runtime health, and jump into deep investigation tools.
        </p>
        <p :if={@diagnostic_warning} class="mt-2 text-xs text-js-warning">{@diagnostic_warning}</p>
      </.card>

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
            <div
              :for={snapshot <- @node_snapshots}
              class="py-2 flex items-start justify-between gap-3"
            >
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

  defp bool_label(true), do: "available"
  defp bool_label(false), do: "not available"

  defp page_path(prefix, suffix, runtime_key, node_param) do
    ScopeQuery.with_scope_query(prefix <> suffix, runtime_key, node_param)
  end
end
