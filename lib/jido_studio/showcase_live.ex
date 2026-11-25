defmodule JidoStudio.ShowcaseLive do
  @moduledoc false
  use Phoenix.LiveView

  import JidoStudio.Components

  alias JidoStudio.Mount

  @statuses [
    {"All statuses", ""},
    {"Online", "online"},
    {"Busy", "busy"},
    {"Idle", "idle"},
    {"Failed", "error"},
    {"Offline", "offline"}
  ]
  @status_values Enum.map(@statuses, &elem(&1, 1))

  @instances [
    %{
      name: "Signal Runner",
      id: "signal-runner-01",
      status: :online,
      label: "Online",
      tone: :success,
      activity: "Just now"
    },
    %{
      name: "Device Control",
      id: "device-control-02",
      status: :busy,
      label: "Busy",
      tone: :warning,
      activity: "12 sec ago"
    },
    %{
      name: "Order Review",
      id: "order-review-03",
      status: :idle,
      label: "Idle",
      tone: :info,
      activity: "2 min ago"
    },
    %{
      name: "Scheduler",
      id: "scheduler-04",
      status: :error,
      label: "Failed",
      tone: :error,
      activity: "8 min ago"
    },
    %{
      name: "Report Agent",
      id: "report-agent-05",
      status: :offline,
      label: "Offline",
      tone: :neutral,
      activity: "Yesterday"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Design components", statuses: @statuses)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    tab = if params["tab"] in ~w(empty unavailable), do: params["tab"], else: "instances"
    filters = normalize_filters(params)

    {:noreply,
     assign(socket,
       tab: tab,
       filter_query: filters,
       filter_form: to_form(Map.merge(%{"q" => "", "status" => ""}, filters), as: :filters),
       instances: Enum.filter(@instances, &matches?(&1, filters))
     )}
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => params}, socket) when is_map(params) do
    %{studio_path: mount, studio_scope: scope} = socket.assigns
    {:noreply, push_patch(socket, to: showcase_path(mount, scope, normalize_filters(params)))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id="studio-showcase">
      <.page_header
        title="Design components"
        subtitle="Shared Studio components with sample data for visual review."
      >
        <:actions>
          <.button data-studio-open-dialog="studio-preview-dialog">Preview dialog</.button>
        </:actions>
      </.page_header>

      <div class="studio-stats" aria-label="Count card examples">
        <.stat_card
          label="Running instances"
          value="3"
          change="5 registered"
          tone={:success}
        />
        <.stat_card label="Recent events" value="248" change="Past hour" />
        <.stat_card label="Failed runs" value="2" change="1 needs review" tone={:error} />
      </div>

      <div class="studio-showcase-grid">
        <.card id="studio-table-card">
          <div class="studio-card-header">
            <div>
              <h2>Agent instances</h2>
            </div>
            <.tabs active={@tab} label="Instance table examples">
              <:tab
                id="instances"
                label="Instances"
                patch={showcase_path(@studio_path, @studio_scope, @filter_query)}
              />
              <:tab
                id="empty"
                label="Empty state"
                patch={
                  showcase_path(@studio_path, @studio_scope, Map.put(@filter_query, "tab", "empty"))
                }
              />
              <:tab
                id="unavailable"
                label="Unavailable"
                patch={
                  showcase_path(
                    @studio_path,
                    @studio_scope,
                    Map.put(@filter_query, "tab", "unavailable")
                  )
                }
              />
            </.tabs>
          </div>

          <.form
            :if={@tab == "instances"}
            for={@filter_form}
            id="studio-instance-filters"
            class="studio-filter-bar"
            phx-submit="apply_filters"
            role="search"
            aria-label="Filter sample instances"
          >
            <.field
              field={@filter_form[:q]}
              label="Find an agent"
              placeholder="Name or instance ID"
              autocomplete="off"
              maxlength="80"
            />
            <.field field={@filter_form[:status]} label="Status" type="select" options={@statuses} />
            <div class="studio-actions">
              <.button type="submit" variant={:secondary}>Filter</.button>
              <.link
                :if={@filter_query != %{} && @instances != []}
                class="studio-button studio-button-ghost studio-button-md"
                patch={showcase_path(@studio_path, @studio_scope)}
              >
                Clear
              </.link>
            </div>
          </.form>

          <.data_table
            :if={@tab == "instances" && @instances != []}
            rows={@instances}
            label="Sample instances"
          >
            <:col :let={row} label="Agent" row_header>
              <span class="studio-table-identity">{row.name}<code>{row.id}</code></span>
            </:col>
            <:col :let={row} label="Status">
              <.badge variant={row.tone}>
                <.status_dot status={row.status} />
                {row.label}
              </.badge>
            </:col>
            <:col :let={row} label="Last activity">{row.activity}</:col>
          </.data_table>

          <.empty_state
            :if={@tab == "instances" && @instances == []}
            title="No matching instances"
            description="Change the name, instance ID, or status filter."
          >
            <.link
              class="studio-button studio-button-secondary studio-button-sm"
              patch={showcase_path(@studio_path, @studio_scope)}
            >
              Clear filters
            </.link>
          </.empty_state>

          <.empty_state
            :if={@tab == "empty"}
            title="No instances found"
            description="Running instances appear here."
          >
            <.link
              class="studio-button studio-button-secondary studio-button-sm"
              patch={showcase_path(@studio_path, @studio_scope, @filter_query)}
            >
              Show sample instances
            </.link>
          </.empty_state>

          <.notice :if={@tab == "unavailable"} title="Runtime unavailable" tone={:warning}>
            Studio could not connect to the selected runtime. The instance list is unavailable.
            <:actions>
              <.link
                class="studio-button studio-button-secondary studio-button-sm"
                patch={showcase_path(@studio_path, @studio_scope, @filter_query)}
              >
                Show sample instances
              </.link>
            </:actions>
          </.notice>
        </.card>

        <div class="studio-showcase-controls">
          <.card>
            <h2>Status</h2>
            <div class="studio-actions">
              <.badge>Neutral</.badge>
              <.badge variant={:success}>Success</.badge>
              <.badge variant={:warning}>Warning</.badge>
              <.badge variant={:error}>Error</.badge>
              <.badge variant={:info}>Info</.badge>
            </div>
          </.card>

          <.card>
            <h2>Buttons</h2>
            <div class="studio-actions" id="studio-button-examples">
              <.button
                :for={variant <- [:primary, :secondary, :ghost, :destructive]}
                variant={variant}
                size={:sm}
                data-studio-open-dialog="studio-preview-dialog"
              >
                {variant |> Atom.to_string() |> String.capitalize()}
              </.button>
              <.button variant={:secondary} size={:sm} disabled>Disabled</.button>
            </div>
          </.card>
        </div>
      </div>

      <.card id="studio-pane-example">
        <div class="studio-card-header">
          <div>
            <h2>Workbench layout</h2>
            <p>Scroll each pane on desktop. The panes stack on narrow screens.</p>
          </div>
        </div>
        <.panes label="Events">
          <:left label="Sessions">
            <h3>Sessions</h3>
            <ul class="studio-preview-list">
              <li>Order review</li>
              <li>Device check</li>
              <li>Signal test</li>
            </ul>
          </:left>
          <h3>Events</h3>
          <ol class="studio-preview-list">
            <li :for={number <- 1..9}><code>event-{number}</code> · Sample activity</li>
          </ol>
          <:right label="Instance">
            <h3>Instance</h3>
            <p><.status_dot status={:online} /> <span>Online</span></p>
            <code>signal-runner-01</code>
          </:right>
        </.panes>
      </.card>

      <.dialog
        id="studio-preview-dialog"
        title="Signal Runner"
        description="Instance signal-runner-01 is online."
      />
    </div>
    """
  end

  defp showcase_path(mount, scope, query \\ %{}) do
    Mount.path(mount, "/components", Map.merge(scope, query))
  end

  defp normalize_filters(params) do
    query =
      if is_binary(params["q"]), do: params["q"] |> String.trim() |> String.slice(0, 80), else: ""

    status = if params["status"] in @status_values, do: params["status"], else: ""
    Map.reject(%{"q" => query, "status" => status}, fn {_key, value} -> value == "" end)
  end

  defp matches?(instance, filters) do
    query = String.downcase(Map.get(filters, "q", ""))

    status_matches =
      !Map.has_key?(filters, "status") || Atom.to_string(instance.status) == filters["status"]

    status_matches &&
      (String.contains?(String.downcase(instance.name), query) ||
         String.contains?(instance.id, query))
  end
end
