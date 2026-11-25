defmodule JidoStudio.DefinitionOverviewComponents do
  @moduledoc false

  use Phoenix.Component

  attr :definition, :map, required: true
  attr :signal_path, :any, required: true
  attr :selected, :string, required: true

  def topology(assigns) do
    topology = assigns.definition["topology"]
    members = topology["members"]
    connections = topology["connections"]

    endpoints =
      connections
      |> Enum.flat_map(&[&1["from"], &1["to"]])
      |> Enum.uniq()
      |> Enum.filter(&(&1["kind"] != "agent"))

    groups = Enum.chunk_by(connections, &{&1["signal"], &1["from"]})

    assigns =
      assign(assigns,
        members: members,
        endpoints: endpoints,
        groups: groups,
        count: Enum.sum(Enum.map(members, & &1["count"])),
        connection_count: length(connections),
        signals: MapSet.new(assigns.definition["routes"], & &1["signal"])
      )

    ~H"""
    <section id="studio-definition-topology" aria-labelledby="studio-definition-topology-title">
      <header class="studio-definition-section-header">
        <h2 id="studio-definition-topology-title">Signal topology</h2>
        <p>1 root · {@count} members · {@connection_count} declared connections</p>
      </header>

      <ul class="studio-definition-actors" aria-label="Declared participants">
        <li class="studio-definition-block" data-kind="root">
          <span>Root agent</span>
          <h3>{label(@definition["name"])}</h3>
        </li>
        <li :for={endpoint <- @endpoints} class="studio-definition-block" data-kind="bus">
          <span>{label(endpoint["kind"])}</span>
          <h3>{label(endpoint["name"])}</h3>
          <code>{endpoint["name"]}</code>
        </li>
        <li :for={member <- @members} class="studio-definition-block" data-kind="member">
          <span>Agent member · ×{member["count"]}</span>
          <h3>{label(member["name"])}</h3>
          <code>{member["definition"]}</code>
          <details :if={member["routes"] != []}>
            <summary>Member routes</summary>
            <ul>
              <li :for={route <- member["routes"]}>
                <code>{route["signal"]}</code> · {label(route["handler"]["kind"])}
              </li>
            </ul>
          </details>
        </li>
      </ul>

      <ul class="studio-definition-connections" aria-label="Declared signal connections">
        <li
          :for={group <- @groups}
          class="studio-definition-connection"
          data-selected={if hd(group)["signal"] == @selected, do: "true"}
        >
          <% first = hd(group) %>
          <span class="studio-definition-endpoint">
            {endpoint_label(first["from"], @definition["name"])}
          </span>
          <span class="studio-definition-connection-signal">
            <.link
              :if={MapSet.member?(@signals, first["signal"])}
              patch={@signal_path.(first["signal"])}
            >
              <code>{first["signal"]}</code>
            </.link>
            <code :if={!MapSet.member?(@signals, first["signal"])}>{first["signal"]}</code>
          </span>
          <ul class="studio-definition-destinations">
            <li :for={connection <- group}>
              <span>{endpoint_label(connection["to"], @definition["name"])}</span>
              <span :if={connection["delivery"] != "single"} class="studio-definition-tag">
                {label(connection["delivery"])}
                <%= if member = Enum.find(@members, &(&1["name"] == connection["to"]["name"])) do %>
                  · ×{member["count"]}
                <% end %>
              </span>
            </li>
          </ul>
        </li>
      </ul>
    </section>
    """
  end

  attr :definition, :map, required: true
  attr :signal_path, :any, required: true

  def resources(assigns) do
    ~H"""
    <section id="studio-definition-resources" aria-labelledby="studio-definition-resources-title">
      <header class="studio-definition-section-header">
        <h2 id="studio-definition-resources-title">Configured resources</h2>
      </header>
      <ul class="studio-definition-resources" aria-label="Resources">
        <li :for={resource <- @definition["resources"] || []} class="studio-definition-block">
          <h3>{resource["name"]}</h3>
          <dl class="studio-definition-fields">
            <div :for={item <- resource["items"]}>
              <dt>{label(item["name"])}</dt>
              <dd>{item["detail"]}</dd>
            </div>
          </dl>
        </li>
      </ul>

      <div :if={(@definition["schedules"] || []) != []} class="studio-definition-panel">
        <header class="studio-definition-panel-header">
          <h3>Scheduled inputs</h3>
        </header>
        <ul class="studio-definition-schedules">
          <li :for={schedule <- @definition["schedules"]}>
            <div>
              <strong>{label(schedule["name"])}</strong>
              <span>{timing(schedule["timing"])}</span>
            </div>
            <.link patch={@signal_path.(schedule["signal"])}>
              <code>{schedule["signal"]}</code>
            </.link>
          </li>
        </ul>
      </div>
    </section>
    """
  end

  defp endpoint_label(%{"kind" => "agent", "name" => "root"}, root), do: label(root)
  defp endpoint_label(%{"name" => name}, _root), do: label(name)

  defp timing(%{"kind" => "every", "milliseconds" => ms}) when rem(ms, 60_000) == 0,
    do: "Every #{div(ms, 60_000)} min"

  defp timing(%{"kind" => "every", "milliseconds" => ms}), do: "Every #{ms} ms"

  defp timing(%{"kind" => "cron", "expression" => expression, "timezone" => timezone}),
    do: "Cron #{expression} · #{timezone}"

  defp label(name), do: Phoenix.Naming.humanize(name)
end
