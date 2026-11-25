defmodule JidoStudio.Components do
  @moduledoc false
  use Phoenix.Component

  attr :title, :string, required: true
  attr :subtitle, :string, default: nil
  attr :rest, :global
  slot :actions

  def page_header(assigns) do
    ~H"""
    <header class="studio-page-header" {@rest}>
      <div>
        <h1>{@title}</h1>
        <p :if={@subtitle}>{@subtitle}</p>
      </div>
      <div :if={@actions != []} class="studio-actions">{render_slot(@actions)}</div>
    </header>
    """
  end

  attr :variant, :atom, default: :primary, values: [:primary, :secondary, :ghost, :destructive]
  attr :size, :atom, default: :md, values: [:sm, :md, :lg]
  attr :type, :string, default: "button"
  attr :rest, :global, include: ~w(disabled autofocus)
  slot :inner_block, required: true

  def button(assigns) do
    ~H"""
    <button
      type={@type}
      class={["studio-button", "studio-button-#{@variant}", "studio-button-#{@size}"]}
      {@rest}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  attr :field, Phoenix.HTML.FormField, required: true
  attr :label, :string, required: true
  attr :type, :string, default: "search", values: ["search", "text", "select"]
  attr :options, :list, default: []
  attr :rest, :global, include: ~w(autocomplete maxlength placeholder)

  def field(assigns) do
    ~H"""
    <div class="studio-field">
      <label for={@field.id}>{@label}</label>
      <select :if={@type == "select"} id={@field.id} name={@field.name} {@rest}>
        {Phoenix.HTML.Form.options_for_select(@options, @field.value)}
      </select>
      <input
        :if={@type != "select"}
        type={@type}
        id={@field.id}
        name={@field.name}
        value={Phoenix.HTML.Form.normalize_value(@type, @field.value)}
        {@rest}
      />
    </div>
    """
  end

  attr :class, :string, default: nil
  attr :rest, :global
  slot :inner_block, required: true

  def card(assigns) do
    ~H"""
    <div class={["studio-card", @class]} {@rest}>{render_slot(@inner_block)}</div>
    """
  end

  attr :label, :string, required: true
  attr :value, :string, required: true
  attr :change, :string, default: nil
  attr :tone, :atom, default: :neutral, values: [:neutral, :success, :warning, :error, :info]

  def stat_card(assigns) do
    ~H"""
    <.card class="studio-stat">
      <p class="studio-stat-label">{@label}</p>
      <strong>{@value}</strong>
      <p :if={@change} class={"studio-tone-#{@tone}"}>{@change}</p>
    </.card>
    """
  end

  attr :variant, :atom, default: :neutral, values: [:neutral, :success, :warning, :error, :info]
  slot :inner_block, required: true

  def badge(assigns) do
    ~H"""
    <span class={["studio-badge", "studio-tone-#{@variant}"]}>{render_slot(@inner_block)}</span>
    """
  end

  attr :status, :atom, required: true, values: [:online, :offline, :busy, :idle, :error]

  def status_dot(assigns) do
    ~H"""
    <span class={["studio-status-dot", "studio-status-#{@status}"]} aria-hidden="true"></span>
    """
  end

  attr :rows, :any, required: true
  attr :label, :string, required: true
  attr :id, :string, default: nil

  slot :col, required: true do
    attr :label, :string, required: true
    attr :row_header, :boolean
  end

  def data_table(assigns) do
    assigns = assign(assigns, :stream?, match?(%Phoenix.LiveView.LiveStream{}, assigns.rows))

    ~H"""
    <div class="studio-table-scroll" tabindex="0" role="region" aria-label={@label}>
      <table class="studio-table">
        <thead>
          <tr>
            <th :for={col <- @col} scope="col">{col.label}</th>
          </tr>
        </thead>
        <tbody id={@id} phx-update={if @stream?, do: "stream"}>
          <tr :for={entry <- @rows} id={if @stream?, do: elem(entry, 0)}>
            <% row = if @stream?, do: elem(entry, 1), else: entry %>
            <%= for col <- @col do %>
              <th :if={col[:row_header]} scope="row">{render_slot(col, row)}</th>
              <td :if={!col[:row_header]}>{render_slot(col, row)}</td>
            <% end %>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end

  attr :active, :string, required: true
  attr :label, :string, required: true

  slot :tab, required: true do
    attr :id, :string, required: true
    attr :label, :string, required: true
    attr :patch, :string, required: true
  end

  def tabs(assigns) do
    ~H"""
    <nav class="studio-tabs" aria-label={@label}>
      <.link :for={tab <- @tab} patch={tab.patch} aria-current={if tab.id == @active, do: "page"}>
        {tab.label}
      </.link>
    </nav>
    """
  end

  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block

  def empty_state(assigns) do
    ~H"""
    <div class="studio-empty">
      <p class="studio-empty-title">{@title}</p>
      <p :if={@description}>{@description}</p>
      <div :if={@inner_block != []}>{render_slot(@inner_block)}</div>
    </div>
    """
  end

  attr :title, :string, required: true
  attr :tone, :atom, default: :info, values: [:success, :warning, :error, :info]
  slot :inner_block, required: true
  slot :actions

  def notice(assigns) do
    ~H"""
    <div class={["studio-notice", "studio-tone-#{@tone}"]}>
      <p class="studio-notice-title">{@title}</p>
      <div class="studio-notice-body">{render_slot(@inner_block)}</div>
      <div :if={@actions != []} class="studio-actions">{render_slot(@actions)}</div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :title, :string, required: true
  attr :description, :string, default: nil
  slot :inner_block

  def dialog(assigns) do
    ~H"""
    <dialog
      id={@id}
      class="studio-dialog"
      aria-labelledby={@id <> "-title"}
      aria-describedby={if @description, do: @id <> "-description"}
    >
      <h2 id={@id <> "-title"}>{@title}</h2>
      <p :if={@description} id={@id <> "-description"}>{@description}</p>
      {render_slot(@inner_block)}
      <form method="dialog" class="studio-actions">
        <.button variant={:secondary} type="submit" autofocus>Close</.button>
      </form>
    </dialog>
    """
  end

  attr :label, :string, required: true

  slot :left, required: true do
    attr :label, :string, required: true
  end

  slot :inner_block, required: true

  slot :right, required: true do
    attr :label, :string, required: true
  end

  def panes(assigns) do
    ~H"""
    <div class="studio-panes">
      <div :for={pane <- @left} tabindex="0" role="region" aria-label={pane.label}>
        {render_slot(pane)}
      </div>
      <div tabindex="0" role="region" aria-label={@label}>{render_slot(@inner_block)}</div>
      <div :for={pane <- @right} tabindex="0" role="region" aria-label={pane.label}>
        {render_slot(pane)}
      </div>
    </div>
    """
  end
end
