defmodule JidoStudio.Setup.Components do
  @moduledoc false
  use Phoenix.Component

  import JidoStudio.Components

  alias JidoStudio.Setup

  attr :checks, :list, required: true

  def checks_list(assigns) do
    ~H"""
    <div class="mt-3 space-y-2">
      <div
        :for={check <- @checks}
        class="rounded-md border border-js-border bg-js-bg-elevated px-3 py-2"
      >
        <div class="flex items-center justify-between gap-2">
          <div class="text-xs text-js-text font-medium">{check.label}</div>
          <.badge variant={Setup.status_badge_variant(check.status)}>
            {Setup.status_label(check.status)}
          </.badge>
        </div>
        <p class="mt-1 text-xs text-js-text-muted">{check.detail}</p>
        <div :if={List.wrap(check.actions) != []} class="mt-2 flex flex-wrap gap-1.5">
          <%= for action <- List.wrap(check.actions) do %>
            <%= if action.kind == :navigate and is_binary(action.path) do %>
              <.link
                navigate={action.path}
                class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text hover:bg-js-bg"
              >
                {action.label}
              </.link>
            <% else %>
              <button
                type="button"
                phx-click={action.event}
                phx-value-value={action[:value]}
                class="inline-flex items-center rounded-md border border-js-border px-2 py-1 text-[11px] text-js-text-muted hover:text-js-text hover:bg-js-bg"
              >
                {action.label}
              </button>
            <% end %>
          <% end %>
        </div>
      </div>
    </div>
    """
  end

  attr :setup_assistant, :map, required: true
  attr :setup_profile, :map, required: true
  attr :heading, :string, default: "Setup Profiles"
  attr :select_event, :string, default: "select_setup_profile"

  def profile_guidance(assigns) do
    ~H"""
    <div class="mt-4 border-t border-js-border pt-3 space-y-2">
      <div class="flex items-center justify-between gap-2">
        <h3 class="text-xs font-semibold uppercase tracking-wider text-js-text-subtle">
          {@heading}
        </h3>
        <.badge variant={:default}>
          {@setup_profile.badge}
        </.badge>
      </div>
      <div class="flex flex-wrap gap-1.5">
        <button
          :for={profile <- @setup_assistant.profiles}
          type="button"
          phx-click={@select_event}
          phx-value-value={profile.key}
          class={[
            "inline-flex items-center rounded-md border px-2 py-1 text-[11px]",
            if(profile.key == @setup_profile.key,
              do: "border-js-info text-js-info bg-js-info/10",
              else: "border-js-border text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"
            )
          ]}
        >
          {profile.label}
        </button>
      </div>

      <div class="rounded-md border border-js-border bg-js-bg-elevated/40 p-3">
        <p class="text-xs font-medium text-js-text">{@setup_profile.label}</p>
        <p class="mt-1 text-xs text-js-text-muted">{@setup_profile.summary}</p>
        <p class="mt-2 text-[11px] uppercase tracking-wide text-js-text-subtle">
          What changes?
        </p>
        <p :for={item <- @setup_profile.changes} class="mt-1 text-[11px] text-js-text-muted">
          - {item}
        </p>
        <p class="mt-2 text-[11px] uppercase tracking-wide text-js-text-subtle">
          Apply profile snippet
        </p>
        <pre class="mt-1 text-[11px] text-js-text-muted bg-js-bg border border-js-border rounded-md p-2 overflow-x-auto whitespace-pre-wrap break-words"><%= @setup_profile.snippet %></pre>
        <p class="mt-2 text-[11px] text-js-text-muted">
          <span class="font-medium text-js-text-subtle">Rollback:</span> {@setup_profile.rollback}
        </p>
      </div>
    </div>
    """
  end
end
