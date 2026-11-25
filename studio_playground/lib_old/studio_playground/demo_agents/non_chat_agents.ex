defmodule StudioPlayground.DemoAgents.SignalRunnerAgent do
  @moduledoc false

  use Jido.Agent,
    name: "signal_runner_agent",
    description: "Signal-first demo agent with explicit non-chat routes",
    category: "demo",
    tags: ["demo", "non-chat", "signals"],
    schema: [
      ping_count: [type: :non_neg_integer, default: 0],
      last_message: [type: :string, default: ""],
      last_seen_at: [type: :integer, default: 0]
    ]

  @impl true
  def signal_routes(_ctx) do
    [
      {"demo.ping", StudioPlayground.DemoAgents.Actions.RecordPing},
      {"demo.echo", StudioPlayground.DemoAgents.Actions.RecordEcho},
      {"demo.reset", StudioPlayground.DemoAgents.Actions.ResetSignalState}
    ]
  end
end

defmodule StudioPlayground.DemoAgents.DeviceControlAgent do
  @moduledoc false

  use Jido.Agent,
    name: "device_control_agent",
    description: "Schema-heavy control agent for runner payload experiments",
    category: "operations",
    tags: ["demo", "non-chat", "internal"],
    schema: [
      mode: [type: :string, default: "idle"],
      target_temp_f: [type: :float, default: 72.0],
      fan_enabled: [type: :boolean, default: false],
      notes: [type: :string, default: ""],
      last_command: [type: :string, default: ""]
    ]

  @impl true
  def signal_routes(_ctx) do
    [
      {"device.set_mode", StudioPlayground.DemoAgents.Actions.SetMode},
      {"device.configure", StudioPlayground.DemoAgents.Actions.ConfigureDevice},
      {"device.shutdown", StudioPlayground.DemoAgents.Actions.ShutdownDevice}
    ]
  end
end

defmodule StudioPlayground.DemoAgents.Actions.RecordPing do
  @moduledoc false

  use Jido.Action,
    name: "record_ping",
    description: "Track ping calls and timestamps",
    schema: [
      message: [type: :string, default: "ping"],
      request_id: [type: :string, required: false]
    ]

  @impl true
  def run(params, _ctx) do
    now_ms = System.system_time(:millisecond)

    {:ok,
     %{
       ping_count: 1,
       last_message: Map.get(params, :message, "ping"),
       last_seen_at: now_ms
     }}
  end
end

defmodule StudioPlayground.DemoAgents.Actions.RecordEcho do
  @moduledoc false

  use Jido.Action,
    name: "record_echo",
    description: "Echo a message into agent state",
    schema: [
      message: [type: :string, required: true],
      source: [type: :string, default: "operator"]
    ]

  @impl true
  def run(params, _ctx) do
    {:ok,
     %{
       last_message: Map.get(params, :message, ""),
       last_command: "echo:" <> Map.get(params, :source, "operator")
     }}
  end
end

defmodule StudioPlayground.DemoAgents.Actions.ResetSignalState do
  @moduledoc false

  use Jido.Action,
    name: "reset_signal_state",
    description: "Reset signal demo state",
    schema: []

  @impl true
  def run(_params, _ctx) do
    {:ok, %{ping_count: 0, last_message: "", last_command: "reset"}}
  end
end

defmodule StudioPlayground.DemoAgents.Actions.SetMode do
  @moduledoc false

  use Jido.Action,
    name: "set_mode",
    description: "Set device mode and capture operator notes",
    schema: [
      mode: [type: :string, required: true],
      notes: [type: :string, required: false]
    ]

  @impl true
  def run(params, _ctx) do
    {:ok,
     %{
       mode: Map.get(params, :mode, "idle"),
       notes: Map.get(params, :notes, ""),
       last_command: "set_mode"
     }}
  end
end

defmodule StudioPlayground.DemoAgents.Actions.ConfigureDevice do
  @moduledoc false

  use Jido.Action,
    name: "configure_device",
    description: "Apply temperature and fan configuration",
    schema: [
      target_temp_f: [type: :float, required: true],
      fan_enabled: [type: :boolean, default: false],
      notes: [type: :string, required: false]
    ]

  @impl true
  def run(params, _ctx) do
    {:ok,
     %{
       target_temp_f: Map.get(params, :target_temp_f, 72.0),
       fan_enabled: Map.get(params, :fan_enabled, false),
       notes: Map.get(params, :notes, ""),
       last_command: "configure"
     }}
  end
end

defmodule StudioPlayground.DemoAgents.Actions.ShutdownDevice do
  @moduledoc false

  use Jido.Action,
    name: "shutdown_device",
    description: "Shutdown the device safely",
    schema: [
      reason: [type: :string, default: "manual"]
    ]

  @impl true
  def run(params, _ctx) do
    {:ok,
     %{
       mode: "offline",
       fan_enabled: false,
       last_command: "shutdown:" <> Map.get(params, :reason, "manual")
     }}
  end
end
