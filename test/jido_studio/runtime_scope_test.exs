defmodule JidoStudio.RuntimeScopeTest do
  use ExUnit.Case, async: false

  alias JidoStudio.RuntimeScope

  setup do
    previous_jido_instance = Application.get_env(:jido_studio, :jido_instance, :__unset__)
    previous_jido_instances = Application.get_env(:jido_studio, :jido_instances, :__unset__)

    on_exit(fn ->
      restore_env(:jido_instance, previous_jido_instance)
      restore_env(:jido_instances, previous_jido_instances)
      RuntimeScope.put_process_runtime_key(nil, [])
    end)

    :ok
  end

  test "derives a single runtime option from jido_instance config" do
    Application.put_env(:jido_studio, :jido_instance, JidoStudio.TestJido)
    Application.delete_env(:jido_studio, :jido_instances)

    options = RuntimeScope.runtime_options()

    assert [%{key: "default", module: JidoStudio.TestJido}] = options
    assert RuntimeScope.default_runtime_key(options) == "default"
    assert RuntimeScope.normalize_runtime_key("missing", options) == "default"
    assert RuntimeScope.runtime_module_for_key(options, "default") == JidoStudio.TestJido
  end

  test "uses explicit multi-runtime config when present" do
    Application.put_env(:jido_studio, :jido_instances, [
      %{key: "primary", module: JidoStudio.TestJido, label: "Primary"},
      %{key: "backup", module: JidoStudio.AgentRegistry, label: "Backup"}
    ])

    options = RuntimeScope.runtime_options(JidoStudio.TestJido)

    assert Enum.map(options, & &1.key) == ["primary", "backup"]
    assert RuntimeScope.default_runtime_key(options) == "primary"
    assert RuntimeScope.normalize_runtime_key("backup", options) == "backup"
    assert RuntimeScope.runtime_module_for_key(options, "backup") == JidoStudio.AgentRegistry
  end

  test "invalid runtime key falls back and yields warning" do
    options = [
      %{key: "primary", module: JidoStudio.TestJido, label: "Primary"}
    ]

    selected = RuntimeScope.normalize_runtime_key("unknown", options)
    warning = RuntimeScope.runtime_warning("unknown", selected, options)

    assert selected == "primary"
    assert warning =~ "Selected runtime unknown is unavailable."
    assert warning =~ "Using Primary."
  end

  test "process runtime key storage allows nil and valid keys" do
    options = [
      %{key: "primary", module: JidoStudio.TestJido, label: "Primary"},
      %{key: "backup", module: JidoStudio.AgentRegistry, label: "Backup"}
    ]

    assert :ok == RuntimeScope.put_process_runtime_key(nil, options)
    assert RuntimeScope.current_runtime_key(options) == nil

    assert :ok == RuntimeScope.put_process_runtime_key("backup", options)
    assert RuntimeScope.current_runtime_key(options) == "backup"
  end

  defp restore_env(key, :__unset__), do: Application.delete_env(:jido_studio, key)
  defp restore_env(key, value), do: Application.put_env(:jido_studio, key, value)
end
