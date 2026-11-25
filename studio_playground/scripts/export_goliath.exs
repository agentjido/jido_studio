[destination] = System.argv()

Code.require_file("../../lib/jido_studio/definition_snapshot.ex", __DIR__)

visual = Jido.Lab.Goliath.visual_map()
root = Map.fetch!(visual.agents, visual.root)

graphs =
  Map.new(visual.flows, fn {module, flow} ->
    {module, Jido.Flow.Graph.analyze(flow.components)}
  end)

plugins = Map.new(root.plugins, &{&1.provider, &1.data})

# These labels give readers a short path into the fixture. The routes, replies,
# bindings, and topology come from the compiled definition.
featured = [
  %{
    signal: "goliath.review.requested",
    label: "Request review",
    summary: "Build a review packet and wait for a decision."
  },
  %{
    signal: "goliath.incident.open",
    label: "Open incident",
    summary: "Write an incident record and return a receipt."
  },
  %{
    signal: "goliath.evidence.collect",
    label: "Collect evidence",
    summary: "Queue the request and broadcast it through the audit bus."
  },
  %{
    signal: "goliath.sources.collect",
    label: "Collect sources",
    summary: "Read the GitHub pull request and Zendesk ticket in parallel."
  }
]

item = fn name, detail -> %{name: to_string(name), detail: detail} end
memory = plugins[Jido.Memory.Plugin]
harness = plugins[Jido.Harness.Plugin]

resources = [
  %{
    name: "Chat",
    items:
      Enum.map(plugins[Jido.Chat.Plugin].connections, fn connection ->
        adapter = connection.client.adapter |> Module.split() |> Enum.at(-2)
        item.(connection.name, adapter)
      end)
  },
  %{
    name: "Connect",
    items:
      Enum.map(plugins[Jido.Connect.Plugin].bindings, fn binding ->
        item.(binding.name, binding.integration |> Module.split() |> List.last())
      end)
  },
  %{
    name: "Harness",
    items: [
      item.(harness.provider, harness.sandbox_mode |> to_string() |> String.replace("_", "-"))
    ]
  },
  %{
    name: "Realms",
    items:
      Enum.map(plugins[Jido.Realm.Plugin].realms, fn realm ->
        item.(realm.name, to_string(realm.profile))
      end)
  },
  %{
    name: "Memory",
    items:
      Enum.map(Enum.sort(memory.collections), fn {name, collection} ->
        detail =
          case collection do
            %{max_entries: limit} -> "#{limit} entries"
            %{store: _store} -> "External store"
            _collection -> "Collection"
          end

        item.(name, detail)
      end)
  },
  %{
    name: "Incident records",
    items:
      Enum.map(Enum.sort(memory.bindings.source.incident_records), fn {name, action} ->
        item.(name, inspect(action))
      end)
  }
]

schedules =
  Enum.map(plugins[Jido.Plugin.Timer.DSL].schedules, fn schedule ->
    timing = Map.take(schedule.timing, [:kind, :milliseconds, :expression, :timezone])
    %{name: to_string(schedule.name), signal: schedule.signal.type, timing: timing}
  end)

snapshot =
  visual
  |> JidoStudio.DefinitionSnapshot.from_visual_map(graphs)
  |> Map.merge(%{"featured" => featured, "resources" => resources, "schedules" => schedules})
  |> Jason.encode!(pretty: true)

File.write!(destination, snapshot <> "\n")
