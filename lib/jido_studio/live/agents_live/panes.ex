defmodule JidoStudio.Live.AgentsLive.Panes do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components
  import JidoStudio.Live.AgentsLive.Support

  attr :agent, :map, required: true
  attr :module_path, :string, required: true
  attr :instance_links, :list, required: true
  attr :active_instance_id, :string, default: nil
  attr :traces_path, :string, default: nil
  attr :instance_debug_enabled?, :boolean, default: false
  attr :instance_debug_level, :string, default: "off"
  attr :instance_debug_error, :any, default: nil
  attr :summary_meta, :list, default: []
  attr :instance_observability_events, :list, default: []
  attr :triage_links, :map, default: %{}
  attr :class, :string, default: nil

  def summary_pane(assigns) do
    ~H"""
    <.card class={"js-agent-summary-pane p-0 overflow-hidden flex flex-col min-h-0 #{@class || ""}"}>
      <div class="js-agent-summary-header px-3 py-3 border-b border-js-border">
        <h3 class="text-xl font-semibold text-js-text">{humanize_agent_name(@agent.name)}</h3>
        <div class="mt-1.5">
          <.badge>{@agent.name}</.badge>
        </div>

        <div :if={@instance_links != []} class="mt-2.5 space-y-1.5">
          <div class="text-xs uppercase tracking-wider text-js-text-subtle">Running Instances</div>
          <div class="flex flex-wrap gap-1">
            <.link navigate={@module_path}>
              <.badge variant={:default}>Module</.badge>
            </.link>
            <.link :for={instance <- @instance_links} navigate={instance.path}>
              <.badge variant={if(instance.id == @active_instance_id, do: :info, else: :default)}>
                {short_instance_id(instance.id)}
              </.badge>
            </.link>
          </div>
        </div>

        <div :if={@active_instance_id} class="mt-3 flex items-center justify-between gap-2">
          <div class="text-xs uppercase tracking-wider text-js-text-subtle">Debug Buffer</div>
          <div class="inline-flex items-center gap-1">
            <button
              type="button"
              phx-click="set_debug_level"
              phx-value-level="off"
              class={debug_level_button_class(@instance_debug_level == "off")}
            >
              Off
            </button>
            <button
              type="button"
              phx-click="set_debug_level"
              phx-value-level="on"
              class={debug_level_button_class(@instance_debug_level == "on")}
            >
              On
            </button>
            <button
              type="button"
              phx-click="set_debug_level"
              phx-value-level="verbose"
              class={debug_level_button_class(@instance_debug_level == "verbose")}
            >
              Verbose
            </button>
          </div>
        </div>

        <p
          :if={not is_nil(@active_instance_id) and @instance_debug_error == :debug_not_enabled}
          class="mt-2 text-xs text-js-text-subtle"
        >
          Debug buffer is currently disabled for this instance.
        </p>
      </div>

      <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-3 flex-1 min-h-0">
        <div>
          <h4 class="text-xs uppercase tracking-wider text-js-text-subtle mb-2">Overview</h4>
          <div class="flex flex-wrap gap-1.5">
            <.badge
              :for={{label, value, variant} <- @summary_meta}
              variant={variant}
            >
              {label}: {value}
            </.badge>
          </div>
        </div>

        <div :if={map_size(@triage_links || %{}) > 0}>
          <div class="flex items-center justify-between gap-2 mb-2">
            <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">Live Triage</h4>
          </div>
          <div class="flex flex-wrap gap-2">
            <.link
              :if={is_binary(@triage_links[:latest_incident_path])}
              navigate={@triage_links[:latest_incident_path]}
              class="js-agent-summary-link inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Latest Incident
            </.link>
            <.link
              :if={is_binary(@triage_links[:failures_path])}
              navigate={@triage_links[:failures_path]}
              class="js-agent-summary-link inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Recent Failures
            </.link>
            <.link
              :if={is_binary(@triage_links[:snapshot_path])}
              navigate={@triage_links[:snapshot_path]}
              class="js-agent-summary-link inline-flex items-center rounded-md border border-js-border px-2 py-1 text-xs text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            >
              Correlated Snapshot
            </.link>
          </div>
        </div>

        <div>
          <div class="flex items-center justify-between gap-2 mb-2">
            <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">Recent Events</h4>
            <.link
              :if={@traces_path}
              navigate={@traces_path}
              class="text-xs text-js-info hover:text-js-text transition-colors"
            >
              View all
            </.link>
          </div>
          <%= if @instance_observability_events == [] do %>
            <p class="text-xs text-js-text-subtle">No events captured yet for this instance.</p>
          <% else %>
            <div class="space-y-1.5">
              <div
                :for={event <- Enum.take(@instance_observability_events, 3)}
                class="js-agent-summary-event rounded-md border border-js-border bg-js-bg-elevated/40 px-2 py-1.5"
              >
                <div class="flex items-center justify-between gap-2">
                  <time
                    class="text-[11px] font-mono text-js-text-subtle"
                    data-js-ts={event[:timestamp_ms]}
                    data-js-relative="true"
                  >
                    {format_event_timestamp(event[:timestamp_ms])}
                  </time>
                  <.badge variant={if(event[:source] == :agent_debug, do: :warning, else: :info)}>
                    {event[:source] || :telemetry}
                  </.badge>
                </div>
                <div class="mt-1 text-xs text-js-text-muted font-mono truncate">
                  {format_event_name(event)}
                </div>
              </div>
            </div>
          <% end %>
        </div>
      </div>
    </.card>
    """
  end

  attr :agent, :map, required: true
  attr :detail_tab, :atom, required: true
  attr :detail_tabs, :list, required: true
  attr :sections_by_tab, :map, required: true
  attr :system_prompt, :string, required: true
  attr :module_path, :string, required: true
  attr :instance_links, :list, required: true
  attr :active_instance_id, :string, default: nil
  attr :active_instance_pid, :any, default: nil
  attr :traces_path, :string, default: nil
  attr :instance_debug_enabled?, :boolean, default: false
  attr :instance_debug_level, :string, default: "off"
  attr :instance_debug_error, :any, default: nil
  attr :instance_observability_events, :list, default: []
  attr :class, :string, default: nil

  def settings_pane(assigns) do
    ~H"""
    <.card class={"p-0 overflow-hidden flex flex-col min-h-0 #{@class || ""}"}>
      <div class="px-3 py-3 border-b border-js-border">
        <h3 class="text-xl font-semibold text-js-text">{humanize_agent_name(@agent.name)}</h3>
        <div class="mt-1.5">
          <.badge>{@agent.name}</.badge>
        </div>

        <div :if={@instance_links != []} class="mt-2.5 space-y-1.5">
          <div class="text-xs uppercase tracking-wider text-js-text-subtle">Running Instances</div>
          <div class="flex flex-wrap gap-1">
            <.link navigate={@module_path}>
              <.badge variant={if(is_nil(@active_instance_id), do: :info, else: :default)}>
                Module
              </.badge>
            </.link>
            <.link :for={instance <- @instance_links} navigate={instance.path}>
              <.badge variant={if(instance.id == @active_instance_id, do: :info, else: :default)}>
                {short_instance_id(instance.id)}
              </.badge>
            </.link>
          </div>
        </div>

        <div :if={@active_instance_id} class="mt-3 flex items-center justify-between gap-2">
          <div class="text-xs uppercase tracking-wider text-js-text-subtle">Debug Buffer</div>
          <div class="inline-flex items-center gap-1">
            <button
              type="button"
              phx-click="set_debug_level"
              phx-value-level="off"
              class={debug_level_button_class(@instance_debug_level == "off")}
            >
              Off
            </button>
            <button
              type="button"
              phx-click="set_debug_level"
              phx-value-level="on"
              class={debug_level_button_class(@instance_debug_level == "on")}
            >
              On
            </button>
            <button
              type="button"
              phx-click="set_debug_level"
              phx-value-level="verbose"
              class={debug_level_button_class(@instance_debug_level == "verbose")}
            >
              Verbose
            </button>
          </div>
        </div>

        <p
          :if={not is_nil(@active_instance_id) and @instance_debug_error == :debug_not_enabled}
          class="mt-2 text-xs text-js-text-subtle"
        >
          Debug buffer is currently disabled for this instance.
        </p>
      </div>

      <div class="px-2 py-2 border-b border-js-border flex flex-wrap items-center gap-1">
        <button
          :for={tab <- @detail_tabs}
          type="button"
          phx-click="select_detail_tab"
          phx-value-tab={tab.id}
          class={[
            "px-3 py-1.5 rounded-md text-xs whitespace-nowrap transition-colors",
            if(@detail_tab == tab.id,
              do: "bg-js-muted text-js-text",
              else: "text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            )
          ]}
        >
          {tab.label}
        </button>
      </div>

      <div class="p-3 overflow-y-auto overflow-x-hidden js-scroll space-y-3.5 flex-1 min-h-0">
        <.detail_section
          :for={section <- Map.get(@sections_by_tab, @detail_tab, [])}
          section={section}
        />

        <div :if={@active_instance_id}>
          <div class="flex items-center justify-between gap-2 mb-2">
            <h4 class="text-xs uppercase tracking-wider text-js-text-subtle">Recent Events</h4>
            <.link
              :if={@traces_path}
              navigate={@traces_path}
              class="text-xs text-js-info hover:text-js-text transition-colors"
            >
              View all
            </.link>
          </div>
          <%= if @instance_observability_events == [] do %>
            <p class="text-xs text-js-text-subtle">No events captured yet for this instance.</p>
          <% else %>
            <div class="space-y-1.5">
              <div
                :for={event <- Enum.take(@instance_observability_events, 10)}
                class="rounded-md border border-js-border bg-js-bg-elevated/40 px-2 py-1.5"
              >
                <div class="flex items-center justify-between gap-2">
                  <time
                    class="text-[11px] font-mono text-js-text-subtle"
                    data-js-ts={event[:timestamp_ms]}
                    data-js-relative="true"
                  >
                    {format_event_timestamp(event[:timestamp_ms])}
                  </time>
                  <.badge variant={if(event[:source] == :agent_debug, do: :warning, else: :info)}>
                    {event[:source] || :telemetry}
                  </.badge>
                </div>
                <div class="mt-1 text-xs text-js-text-muted font-mono truncate">
                  {format_event_name(event)}
                </div>
              </div>
            </div>
          <% end %>
        </div>

        <div class="mt-6">
          <h4 class="text-xs uppercase tracking-wider text-js-text-subtle mb-2">System Prompt</h4>
          <pre class="text-xs text-js-text-muted bg-js-bg-elevated border border-js-border rounded-md p-3 whitespace-pre-wrap break-words overflow-x-hidden"><%= @system_prompt %></pre>
        </div>
      </div>
    </.card>
    """
  end

  attr :section, :map, required: true

  def detail_section(assigns) do
    ~H"""
    <div>
      <h4 class="text-xs uppercase tracking-wider text-js-text-subtle mb-2">{@section.title}</h4>
      <%= case @section.kind do %>
        <% :badge -> %>
          <.badge variant={Map.get(@section, :variant, :default)}>{@section.data}</.badge>
        <% :badges -> %>
          <div class="flex flex-wrap gap-1">
            <.badge :for={item <- List.wrap(@section.data)}>{item}</.badge>
          </div>
        <% :kv -> %>
          <div class="space-y-1">
            <div :for={{key, value} <- section_rows(@section.data)} class="text-xs text-js-text-muted">
              <span class="text-js-text-subtle">{key}:</span> {value}
            </div>
          </div>
        <% :code -> %>
          <pre class="text-xs text-js-text-muted bg-js-bg-elevated border border-js-border rounded-md p-3 whitespace-pre-wrap break-words overflow-x-auto"><%= @section.data %></pre>
        <% _ -> %>
          <p class="text-sm text-js-text-muted">{@section.data}</p>
      <% end %>
    </div>
    """
  end

  attr :show, :boolean, required: true
  attr :start_form, :map, required: true
  attr :start_form_schema, :list, required: true
  attr :start_form_error, :string, default: nil
  attr :starting_instance?, :boolean, default: false

  def start_instance_modal(assigns) do
    ~H"""
    <div
      :if={@show}
      class="fixed inset-0 z-50 flex items-center justify-center p-4"
      phx-window-keydown="close_start_modal"
      phx-key="escape"
    >
      <button
        type="button"
        class="absolute inset-0 bg-black/60 backdrop-blur-sm"
        phx-click="close_start_modal"
        aria-label="Close modal"
      />

      <div class="relative w-full max-w-lg rounded-xl bg-js-card border border-js-border p-6 shadow-2xl">
        <button
          type="button"
          phx-click="close_start_modal"
          class="absolute top-4 right-4 text-js-text-muted hover:text-js-text transition-colors"
          aria-label="close"
        >
          <svg
            xmlns="http://www.w3.org/2000/svg"
            class="h-5 w-5"
            viewBox="0 0 20 20"
            fill="currentColor"
          >
            <path
              fill-rule="evenodd"
              d="M4.293 4.293a1 1 0 011.414 0L10 8.586l4.293-4.293a1 1 0 111.414 1.414L11.414 10l4.293 4.293a1 1 0 01-1.414 1.414L10 11.414l-4.293 4.293a1 1 0 01-1.414-1.414L8.586 10 4.293 5.707a1 1 0 010-1.414z"
              clip-rule="evenodd"
            />
          </svg>
        </button>

        <div class="space-y-4">
          <div>
            <h3 id="start-instance-modal-title" class="text-lg font-semibold text-js-text">
              Start Instance
            </h3>
            <p class="text-sm text-js-text-muted mt-1">
              Configure optional startup fields for this agent instance.
            </p>
          </div>

          <div
            :if={@start_form_error}
            class="rounded-md border border-js-error/40 bg-js-error/10 p-3 text-sm text-js-error"
          >
            {@start_form_error}
          </div>

          <form
            phx-change="update_start_form"
            phx-submit="start_instance_with_options"
            class="space-y-4"
          >
            <div :for={field <- @start_form_schema} class="space-y-1">
              <%= case field.type do %>
                <% :checkbox -> %>
                  <div class="space-y-2">
                    <label class="text-xs uppercase tracking-wider text-js-text-subtle">
                      Options
                    </label>
                    <div class="flex items-center gap-2">
                      <input type="hidden" name={"start[#{field.name}]"} value="false" />
                      <input
                        id={start_field_id(field.name)}
                        type="checkbox"
                        name={"start[#{field.name}]"}
                        value="true"
                        checked={Map.get(@start_form, field.name, "false") == "true"}
                        class="h-4 w-4 rounded border-js-border bg-js-bg-elevated text-js-primary focus:ring-js-ring"
                      />
                      <label for={start_field_id(field.name)} class="text-sm text-js-text-muted">
                        {field.label}
                      </label>
                    </div>
                  </div>
                <% :textarea_json -> %>
                  <label
                    for={start_field_id(field.name)}
                    class="text-xs uppercase tracking-wider text-js-text-subtle"
                  >
                    {field.label}
                  </label>
                  <textarea
                    id={start_field_id(field.name)}
                    name={"start[#{field.name}]"}
                    rows={Map.get(field, :rows, 6)}
                    placeholder={Map.get(field, :placeholder, "")}
                    class="w-full rounded-md border border-js-border bg-js-bg-elevated p-2 text-sm text-js-text font-mono focus:outline-none focus:ring-2 focus:ring-js-ring"
                  ><%= Map.get(@start_form, field.name, "") %></textarea>
                <% _ -> %>
                  <label
                    for={start_field_id(field.name)}
                    class="text-xs uppercase tracking-wider text-js-text-subtle"
                  >
                    {field.label}
                  </label>
                  <input
                    id={start_field_id(field.name)}
                    type="text"
                    name={"start[#{field.name}]"}
                    value={Map.get(@start_form, field.name, "")}
                    placeholder={Map.get(field, :placeholder, "")}
                    class="w-full rounded-md border border-js-border bg-js-bg-elevated p-2 text-sm text-js-text focus:outline-none focus:ring-2 focus:ring-js-ring"
                  />
              <% end %>
              <p :if={Map.get(field, :help)} class="text-xs text-js-text-subtle">
                {field.help}
              </p>
            </div>

            <div class="flex items-center justify-end gap-2 pt-2">
              <.button
                type="button"
                variant={:ghost}
                phx-click="close_start_modal"
                disabled={@starting_instance?}
              >
                Cancel
              </.button>
              <.button type="submit" disabled={@starting_instance?}>
                <%= if @starting_instance? do %>
                  Starting...
                <% else %>
                  Start Instance
                <% end %>
              </.button>
            </div>
          </form>
        </div>
      </div>
    </div>
    """
  end

  def section_rows(data) when is_map(data) do
    Enum.map(data, fn {key, value} -> {to_string(key), to_string(value)} end)
  end

  def section_rows(data) when is_list(data), do: data
  def section_rows(_), do: []
end
