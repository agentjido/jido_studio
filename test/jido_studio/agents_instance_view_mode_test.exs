defmodule JidoStudio.AgentsInstanceViewModeTest do
  use JidoStudio.ConnCase, async: false

  alias JidoStudio.AgentRegistry
  alias JidoStudio.TestJido

  setup do
    case Process.whereis(TestJido) do
      pid when is_pid(pid) ->
        Process.exit(pid, :kill)
        Process.sleep(20)

      _ ->
        :ok
    end

    start_supervised!(TestJido)
    :ok
  end

  test "default instance route opens basic view", %{conn: conn} do
    instance_id = "view-default-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    {:ok, _view, html} = live(conn, "/studio/agents/#{slug}/#{instance_id}")

    assert html =~ "Basic View"
    assert html =~ "2. Set Inputs and Run"
    assert html =~ "Current Agent State"
    assert html =~ "Advanced View"
  end

  test "explicit advanced view query renders legacy workbench shell", %{conn: conn} do
    instance_id = "view-advanced-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?view=advanced")

    assert has_element?(view, ".js-instance-menu-section.is-active", "Play")
    assert has_element?(view, ".js-agent-summary-pane")
  end

  test "legacy panel query resolves to advanced mode without explicit view", %{conn: conn} do
    instance_id = "view-legacy-panel-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?panel=messages")

    assert has_element?(view, ".js-instance-menu-tab.is-active", "Messages")
    assert has_element?(view, ".js-agent-summary-pane")
  end

  defp slug_for_module(module) do
    AgentRegistry.list_agents(jido_instance: TestJido)
    |> Enum.find(&(&1.module == module))
    |> case do
      %{slug: slug} when is_binary(slug) -> slug
      _ -> raise "Unable to resolve slug for #{inspect(module)}"
    end
  end
end
