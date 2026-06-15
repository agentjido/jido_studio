defmodule JidoStudio.Components do
  @moduledoc """
  Foundational UI components for the Jido Studio dark-themed dashboard.

  Provides function components styled with Tailwind utility classes using
  dark tones with green/teal accents matching the agentjido_xyz design system.
  """
  use Phoenix.Component

  alias JidoStudio.Components.ChatComponents

  alias Phoenix.LiveView.JS

  # —————————————————————————————————————————————
  # Icon (dynamic wrapper around Lucideicons)
  # —————————————————————————————————————————————

  attr :name, :atom, required: true
  attr :class, :string, default: "w-5 h-5"

  def icon(assigns) do
    apply(Lucideicons, assigns.name, [assigns])
  end

  # —————————————————————————————————————————————
  # Chat Components (re-export)
  # —————————————————————————————————————————————

  def chat_threads_rail(assigns), do: ChatComponents.chat_threads_rail(assigns)
  def chat_conversation_panel(assigns), do: ChatComponents.chat_conversation_panel(assigns)

  # —————————————————————————————————————————————
  # Button
  # —————————————————————————————————————————————

  attr :variant, :atom,
    default: :primary,
    values: [:primary, :secondary, :ghost, :destructive]

  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :rest, :global, include: ~w(type disabled phx-click phx-target)

  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      class={[
        "inline-flex items-center justify-center rounded-md font-medium transition-colors focus:outline-none focus:ring-2 focus:ring-js-ring focus:ring-offset-2 focus:ring-offset-js-bg disabled:opacity-50 disabled:pointer-events-none",
        variant_classes(@variant),
        size_classes(@size)
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  defp variant_classes(:primary),
    do: "bg-js-primary text-js-primary-foreground hover:brightness-110"

  defp variant_classes(:secondary),
    do: "bg-js-bg-elevated text-js-text hover:brightness-125"

  defp variant_classes(:ghost),
    do: "bg-transparent text-js-text-muted hover:text-js-text hover:bg-js-bg-elevated"

  defp variant_classes(:destructive),
    do: "bg-js-destructive text-js-destructive-foreground hover:brightness-110"

  defp size_classes(:sm), do: "px-3 py-1.5 text-xs"
  defp size_classes(:md), do: "px-4 py-2 text-sm"
  defp size_classes(:lg), do: "px-6 py-3 text-base"

  # —————————————————————————————————————————————
  # Card
  # —————————————————————————————————————————————

  attr :class, :string, default: nil
  attr :rest, :global

  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div
      class={["bg-js-card border border-js-border rounded-lg p-6", @class]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </div>
    """
  end

  # —————————————————————————————————————————————
  # Badge
  # —————————————————————————————————————————————

  attr :variant, :atom,
    default: :default,
    values: [:default, :success, :warning, :error, :info]

  attr :rest, :global

  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span
      class={[
        "inline-flex items-center rounded-full px-2.5 py-0.5 text-xs font-medium",
        badge_classes(@variant)
      ]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </span>
    """
  end

  defp badge_classes(:default), do: "bg-js-muted text-js-text-muted"
  defp badge_classes(:success), do: "bg-js-success/15 text-js-success"
  defp badge_classes(:warning), do: "bg-js-warning/15 text-js-warning"
  defp badge_classes(:error), do: "bg-js-error/15 text-js-error"
  defp badge_classes(:info), do: "bg-js-info/15 text-js-info"

  # —————————————————————————————————————————————
  # Data Table
  # —————————————————————————————————————————————

  attr :rows, :list, required: true
  attr :scroll_x, :boolean, default: true
  attr :rest, :global

  slot :col, required: true do
    attr :label, :string, required: true
  end

  def data_table(assigns) do
    ~H"""
    <div class={if @scroll_x, do: "overflow-x-auto", else: "overflow-hidden"} {@rest}>
      <table class="w-full">
        <thead>
          <tr class="bg-js-bg-surface border-b border-js-border">
            <th
              :for={col <- @col}
              class="px-4 py-3 text-left text-xs font-medium uppercase tracking-wider text-js-text-muted"
            >
              {col.label}
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-js-border">
          <tr :for={row <- @rows} class="hover:bg-js-bg-elevated transition-colors">
            <td :for={col <- @col} class="px-4 py-3 text-sm text-js-text-muted">
              {render_slot(col, row)}
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  # —————————————————————————————————————————————
  # Stat Card
  # —————————————————————————————————————————————

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :change, :string, default: nil
  attr :trend, :atom, default: :neutral, values: [:up, :down, :neutral]

  def stat_card(assigns) do
    ~H"""
    <div class="bg-js-card border border-js-border rounded-lg p-6">
      <p class="text-sm text-js-text-muted">{@label}</p>
      <p class="mt-2 text-2xl font-semibold text-js-text">{@value}</p>
      <p :if={@change} class={["mt-1 text-sm", trend_color(@trend)]}>
        <span :if={@trend == :up}>&#8593; </span>
        <span :if={@trend == :down}>&#8595; </span>
        {@change}
      </p>
    </div>
    """
  end

  defp trend_color(:up), do: "text-js-success"
  defp trend_color(:down), do: "text-js-error"
  defp trend_color(:neutral), do: "text-js-text-muted"

  # —————————————————————————————————————————————
  # Page Header
  # —————————————————————————————————————————————

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :rest, :global

  slot :actions

  def page_header(assigns) do
    ~H"""
    <div class="flex items-center justify-between border-b border-js-border pb-4 mb-6" {@rest}>
      <div>
        <h1 class="text-2xl font-semibold text-js-text">{@title}</h1>
        <p :if={@subtitle} class="mt-1 text-sm text-js-text-muted">{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="flex items-center gap-3">
        {render_slot(@actions)}
      </div>
    </div>
    """
  end

  # —————————————————————————————————————————————
  # Tour Metrics Bridge
  # —————————————————————————————————————————————

  def tour_metric_bridge(assigns) do
    ~H"""
    <button
      type="button"
      class="hidden"
      data-js-tour-metric
      phx-click="tour_metric"
    ></button>
    """
  end

  # —————————————————————————————————————————————
  # Empty State
  # —————————————————————————————————————————————

  attr :title, :string, required: true
  attr :description, :string, default: nil

  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center py-12 text-center">
      <h3 class="text-lg font-medium text-js-text-subtle">{@title}</h3>
      <p :if={@description} class="mt-2 text-sm text-js-text-subtle max-w-md">{@description}</p>
      <div :if={@inner_block != []} class="mt-6">
        {render_slot(@inner_block)}
      </div>
    </div>
    """
  end

  # —————————————————————————————————————————————
  # Tabs
  # —————————————————————————————————————————————

  attr :active, :string, required: true
  attr :rest, :global

  slot :tab, required: true do
    attr :id, :string, required: true
    attr :label, :string, required: true
    attr :patch, :string, required: true
  end

  def tabs(assigns) do
    ~H"""
    <div class="bg-js-bg-elevated rounded-lg p-1 inline-flex" {@rest}>
      <.link
        :for={tab <- @tab}
        patch={tab.patch}
        class={[
          "px-4 py-2 text-sm font-medium rounded-md transition-colors",
          if(tab.id == @active,
            do: "bg-js-muted text-js-text",
            else: "text-js-text-muted hover:text-js-text"
          )
        ]}
      >
        {tab.label}
      </.link>
    </div>
    """
  end

  # —————————————————————————————————————————————
  # Modal
  # —————————————————————————————————————————————

  attr :id, :string, required: true
  attr :show, :boolean, default: false
  attr :on_cancel, JS, default: %JS{}

  slot :inner_block, required: true

  def modal(assigns) do
    ~H"""
    <div
      id={@id}
      phx-mounted={@show && show_modal(@id)}
      phx-remove={hide_modal(@id)}
      data-cancel={JS.exec(@on_cancel, "phx-remove")}
      class="relative z-50 hidden"
    >
      <div
        id={"#{@id}-bg"}
        class="fixed inset-0 bg-black/60 backdrop-blur-sm transition-opacity"
        aria-hidden="true"
      />
      <div
        class="fixed inset-0 overflow-y-auto"
        aria-labelledby={"#{@id}-title"}
        aria-describedby={"#{@id}-description"}
        role="dialog"
        aria-modal="true"
        tabindex="0"
      >
        <div class="flex min-h-full items-center justify-center p-4">
          <div
            id={"#{@id}-container"}
            phx-window-keydown={JS.exec("data-cancel", to: "##{@id}")}
            phx-key="escape"
            phx-click-away={JS.exec("data-cancel", to: "##{@id}")}
            class="relative w-full max-w-lg rounded-xl bg-js-card border border-js-border p-6 shadow-2xl transition"
          >
            <button
              phx-click={JS.exec("data-cancel", to: "##{@id}")}
              type="button"
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
            <div id={"#{@id}-content"}>
              {render_slot(@inner_block)}
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end

  defp show_modal(id) do
    %JS{}
    |> JS.show(to: "##{id}")
    |> JS.show(
      to: "##{id}-bg",
      transition: {"transition-all ease-out duration-300", "opacity-0", "opacity-100"}
    )
    |> JS.show(
      to: "##{id}-container",
      transition:
        {"transition-all ease-out duration-300",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95",
         "opacity-100 translate-y-0 sm:scale-100"}
    )
    |> JS.add_class("overflow-hidden", to: "body")
    |> JS.focus_first(to: "##{id}-content")
  end

  defp hide_modal(id) do
    %JS{}
    |> JS.hide(
      to: "##{id}-bg",
      transition: {"transition-all ease-in duration-200", "opacity-100", "opacity-0"}
    )
    |> JS.hide(
      to: "##{id}-container",
      transition:
        {"transition-all ease-in duration-200", "opacity-100 translate-y-0 sm:scale-100",
         "opacity-0 translate-y-4 sm:translate-y-0 sm:scale-95"}
    )
    |> JS.hide(to: "##{id}", transition: {"block", "block", "hidden"})
    |> JS.remove_class("overflow-hidden", to: "body")
    |> JS.pop_focus()
  end

  # —————————————————————————————————————————————
  # Status Dot
  # —————————————————————————————————————————————

  attr :status, :atom, default: :offline, values: [:online, :offline, :busy, :idle]

  def status_dot(assigns) do
    ~H"""
    <span class={["inline-block w-2 h-2 rounded-full", dot_color(@status)]} />
    """
  end

  defp dot_color(:online), do: "bg-js-success"
  defp dot_color(:offline), do: "bg-js-text-subtle"
  defp dot_color(:busy), do: "bg-js-warning"
  defp dot_color(:idle), do: "bg-js-info"
end
