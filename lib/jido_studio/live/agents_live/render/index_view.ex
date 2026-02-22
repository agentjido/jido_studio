defmodule JidoStudio.Live.AgentsLive.Render.IndexView do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components
  import JidoStudio.Live.AgentsLive.Support

  alias JidoStudio.Live.AgentsLive.ShowState

  def index(assigns) do
    ~H"""
    <div class="p-6 space-y-6">
      <.page_header title="Agents" subtitle="Manage and interact with your AI agents">
        <:actions>
          <.button size={:sm} phx-click="refresh">Refresh</.button>
        </:actions>
      </.page_header>

      <div
        :if={not @jido_configured?}
        class="bg-js-warning/10 border border-js-warning/30 rounded-lg p-4"
      >
        <p class="text-sm text-js-warning">
          No Jido instance configured. Showing discovered agent modules only.
          Set
          <code class="bg-js-bg-elevated px-1 rounded">
            config :jido_studio, jido_instance: MyApp.Jido
          </code>
          to enable runtime agent management.
        </p>
      </div>

      <form phx-change="set_timezone" class="hidden" data-js-timezone-form>
        <input
          type="hidden"
          name="timezone"
          value={@user_timezone}
          data-js-timezone-input
        />
      </form>

      <.card>
        <div class="flex items-center justify-between gap-3 mb-3">
          <h3 class="text-sm font-medium text-js-text">Live Ops Scope</h3>
          <.badge variant={if(@live_ops_realtime?, do: :success, else: :warning)}>
            {if(@live_ops_realtime?, do: "event-driven", else: "polling fallback")}
          </.badge>
        </div>
        <form phx-change="update_scope_filters" class="grid grid-cols-1 md:grid-cols-3 gap-2">
          <label class="text-xs text-js-text-muted">
            Project ID
            <input
              type="text"
              name="scope[project_id]"
              value={@scope_filters.project_id || ""}
              placeholder="project scope"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
          <label class="text-xs text-js-text-muted">
            User ID
            <input
              type="text"
              name="scope[user_id]"
              value={@scope_filters.user_id || ""}
              placeholder="user scope"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
          <label class="text-xs text-js-text-muted">
            Agent ID
            <input
              type="text"
              name="scope[agent_id]"
              value={@scope_filters.agent_id || ""}
              placeholder="instance filter"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
        </form>

        <div class="mt-3 flex flex-wrap items-center gap-2">
          <button
            type="button"
            phx-click="toggle_auto_follow_instances"
            class={
              if(@auto_follow_instances?,
                do:
                  "inline-flex rounded-md border border-js-success/40 bg-js-success/10 px-2.5 py-1 text-xs text-js-success",
                else:
                  "inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text"
              )
            }
          >
            Auto-follow {if(@auto_follow_instances?, do: "on", else: "off")}
          </button>
          <.badge :if={@followed_instance_id} variant={:info}>
            Following: {short_instance_id(@followed_instance_id)}
          </.badge>
          <button
            :if={@followed_instance_id}
            type="button"
            phx-click="unfollow_instance"
            class="inline-flex rounded-md border border-js-border px-2.5 py-1 text-xs text-js-text-muted hover:text-js-text"
          >
            Unfollow
          </button>
        </div>

        <form
          phx-change="update_auto_follow_target"
          class="mt-3 grid grid-cols-1 md:grid-cols-3 gap-2"
        >
          <label class="text-xs text-js-text-muted">
            Auto-follow Instance
            <input
              type="text"
              name="target[instance_id]"
              value={@auto_follow_target.instance_id || ""}
              placeholder="instance id"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
          <label class="text-xs text-js-text-muted">
            Auto-follow Project
            <input
              type="text"
              name="target[project_id]"
              value={@auto_follow_target.project_id || ""}
              placeholder="project id"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
          <label class="text-xs text-js-text-muted">
            Auto-follow User
            <input
              type="text"
              name="target[user_id]"
              value={@auto_follow_target.user_id || ""}
              placeholder="user id"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
        </form>
      </.card>

      <div class="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-4">
        <.stat_card label="Discovered Agents" value={to_string(length(@agents))} />
        <.stat_card label="Running" value={to_string(@running_count)} />
        <.stat_card label="Active Instances" value={to_string(length(@filtered_instances || []))} />
        <.stat_card
          label="Available"
          value={to_string(Enum.count(@agents, &(&1.status == :available)))}
        />
      </div>

      <.card>
        <div class="flex items-center justify-between gap-3 mb-3">
          <h3 class="text-sm font-medium text-js-text">Active Instances</h3>
          <.badge variant={if(@live_ops_presence?, do: :success, else: :warning)}>
            {if(@live_ops_presence?, do: "presence viewers", else: "viewer fallback: 0")}
          </.badge>
        </div>

        <form phx-change="update_instance_filters" class="grid grid-cols-1 md:grid-cols-4 gap-2 mb-3">
          <label class="text-xs text-js-text-muted">
            Status
            <select
              name="filters[status_filter]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="all" selected={@agent_filters.status_filter == "all"}>All</option>
              <option value="running" selected={@agent_filters.status_filter == "running"}>
                Running
              </option>
              <option value="idle" selected={@agent_filters.status_filter == "idle"}>Idle</option>
              <option value="interrupted" selected={@agent_filters.status_filter == "interrupted"}>
                Interrupted
              </option>
              <option value="error" selected={@agent_filters.status_filter == "error"}>Error</option>
              <option value="offline" selected={@agent_filters.status_filter == "offline"}>
                Offline
              </option>
            </select>
          </label>
          <label class="text-xs text-js-text-muted">
            Presence
            <select
              name="filters[presence_filter]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="all" selected={@agent_filters.presence_filter == "all"}>All</option>
              <option value="has_viewers" selected={@agent_filters.presence_filter == "has_viewers"}>
                Has Viewers
              </option>
              <option value="no_viewers" selected={@agent_filters.presence_filter == "no_viewers"}>
                No Viewers
              </option>
            </select>
          </label>
          <label class="text-xs text-js-text-muted">
            Search
            <input
              type="text"
              name="filters[search_query]"
              value={@agent_filters.search_query}
              placeholder="instance, agent, scope"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            />
          </label>
          <label class="text-xs text-js-text-muted">
            Sort
            <select
              name="filters[sort_by]"
              class="mt-1 w-full rounded-md border border-js-border bg-js-bg-elevated px-2 py-1.5 text-xs text-js-text"
            >
              <option value="last_activity" selected={@agent_filters.sort_by == "last_activity"}>
                Last Activity
              </option>
              <option value="viewers" selected={@agent_filters.sort_by == "viewers"}>Viewers</option>
              <option value="uptime" selected={@agent_filters.sort_by == "uptime"}>Uptime</option>
              <option value="name" selected={@agent_filters.sort_by == "name"}>Name</option>
              <option value="status" selected={@agent_filters.sort_by == "status"}>Status</option>
            </select>
          </label>
        </form>

        <%= if @filtered_instances == [] do %>
          <.empty_state
            title="No active instances"
            description="No running instances match your scope and filter settings."
          />
        <% else %>
          <div class="overflow-x-auto">
            <table class="w-full">
              <thead>
                <tr class="bg-js-bg-surface border-b border-js-border">
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Instance
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Agent
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Status
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Last Activity
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Uptime
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Viewers
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Scope
                  </th>
                  <th class="px-3 py-2 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted">
                    Actions
                  </th>
                </tr>
              </thead>
              <tbody class="divide-y divide-js-border">
                <tr
                  :for={row <- @filtered_instances}
                  class="hover:bg-js-bg-elevated/40 transition-colors"
                >
                  <td class="px-3 py-2 text-xs text-js-text font-mono">
                    <span :if={@followed_instance_id == row.instance_id} class="text-js-success mr-1">
                      ●
                    </span>
                    {short_instance_id(row.instance_id)}
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text">
                    <div class="flex items-center gap-1.5">
                      <.link
                        :if={active_instance_path(@prefix, row)}
                        navigate={active_instance_path(@prefix, row)}
                        class="hover:text-js-primary transition-colors"
                      >
                        {humanize_agent_name(row.agent_name || row.agent_slug || "Agent")}
                      </.link>
                      <span :if={is_nil(active_instance_path(@prefix, row))}>
                        {humanize_agent_name(row.agent_name || row.agent_slug || "Agent")}
                      </span>
                      <.badge :if={internal_instance?(row)} variant={:warning}>
                        internal
                      </.badge>
                    </div>
                  </td>
                  <td class="px-3 py-2 text-xs">
                    <.badge variant={status_badge_variant(row.status)}>{row.status}</.badge>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-muted">
                    <time
                      data-js-ts={datetime_to_unix_ms(row.last_activity_at)}
                      data-js-relative={
                        if(datetime_to_unix_ms(row.last_activity_at), do: "true", else: "false")
                      }
                    >
                      {format_datetime(row.last_activity_at)}
                    </time>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text-muted">
                    <span data-js-uptime-ms={row.uptime_ms || ""}>
                      {format_uptime(row.uptime_ms)}
                    </span>
                  </td>
                  <td class="px-3 py-2 text-xs text-js-text">{row.viewer_count || 0}</td>
                  <td class="px-3 py-2 text-xs text-js-text-muted font-mono">
                    {row.project_id || "n/a"} / {row.user_id || "n/a"}
                  </td>
                  <td class="px-3 py-2 text-xs">
                    <div class="flex items-center gap-1">
                      <button
                        :if={@followed_instance_id != row.instance_id}
                        type="button"
                        phx-click="follow_instance"
                        phx-value-id={row.instance_id}
                        class="inline-flex rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text"
                      >
                        Follow
                      </button>
                      <button
                        :if={@followed_instance_id == row.instance_id}
                        type="button"
                        phx-click="unfollow_instance"
                        class="inline-flex rounded-md border border-js-success/40 bg-js-success/10 px-2 py-1 text-[11px] text-js-success"
                      >
                        Following
                      </button>
                      <.link
                        :if={active_instance_path(@prefix, row)}
                        navigate={active_instance_path(@prefix, row)}
                        class="inline-flex rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text"
                      >
                        Open
                      </.link>
                    </div>
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        <% end %>
      </.card>

      <%= if @product_agents == [] and @internal_agents == [] do %>
        <.no_discovered_agents />
      <% else %>
        <.card>
          <div class="flex items-center justify-between gap-2 mb-3">
            <h3 class="text-sm font-medium text-js-text">Product Agents</h3>
            <.badge variant={:default}>{length(@product_agents)}</.badge>
          </div>
          <.data_table rows={@product_agents} scroll_x={false}>
            <:col :let={agent} label="Name">
              <.link
                navigate={agent_module_path(@prefix, agent)}
                class="text-js-text font-medium hover:text-js-primary transition-colors"
              >
                {humanize_agent_name(agent.name)}
              </.link>
            </:col>
            <:col :let={agent} label="Description">
              <span class="text-xs text-js-text-muted truncate max-w-md block">
                {agent.description}
              </span>
            </:col>
            <:col :let={agent} label="Tags">
              <div class="flex flex-wrap gap-1">
                <.badge :for={tag <- agent.tags || []}>{tag}</.badge>
              </div>
            </:col>
            <:col :let={agent} label="Running Instances">
              <span class="text-xs text-js-text-subtle">
                {length(agent.running_instances || [])}
              </span>
            </:col>
          </.data_table>
        </.card>

        <.card :if={@internal_agents != []}>
          <div class="flex items-center justify-between gap-2 mb-3">
            <h3 class="text-sm font-medium text-js-text">Internal Agents</h3>
            <.badge variant={:warning}>{length(@internal_agents)}</.badge>
          </div>
          <.data_table rows={@internal_agents} scroll_x={false}>
            <:col :let={agent} label="Name">
              <.link
                navigate={agent_module_path(@prefix, agent)}
                class="text-js-text font-medium hover:text-js-primary transition-colors"
              >
                {humanize_agent_name(agent.name)}
              </.link>
            </:col>
            <:col :let={agent} label="Description">
              <span class="text-xs text-js-text-muted truncate max-w-md block">
                {agent.description}
              </span>
            </:col>
            <:col :let={agent} label="Tags">
              <div class="flex flex-wrap gap-1">
                <.badge :for={tag <- agent.tags || []} variant={:warning}>{tag}</.badge>
              </div>
            </:col>
            <:col :let={agent} label="Running Instances">
              <span class="text-xs text-js-text-subtle">
                {length(agent.running_instances || [])}
              </span>
            </:col>
          </.data_table>
        </.card>
      <% end %>
    </div>
    """
  end

  def no_discovered_agents(assigns) do
    ~H"""
    <.card>
      <.empty_state
        title="No agents discovered"
        description="No agent modules were found. Make sure your application includes Jido agent definitions."
      />
    </.card>
    """
  end

  defp agent_module_path(prefix, agent), do: ShowState.agent_module_path(prefix, agent)
  defp active_instance_path(prefix, row), do: ShowState.active_instance_path(prefix, row)
  defp status_badge_variant(status), do: ShowState.status_badge_variant(status)
  defp datetime_to_unix_ms(datetime), do: ShowState.datetime_to_unix_ms(datetime)
  defp format_datetime(datetime), do: ShowState.format_datetime(datetime)
  defp format_uptime(ms), do: ShowState.format_uptime(ms)
end
