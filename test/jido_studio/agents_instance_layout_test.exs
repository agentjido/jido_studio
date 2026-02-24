defmodule JidoStudio.AgentsInstanceLayoutTest do
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

  test "summary rail remains mounted across Play, Observe, and Configure", %{conn: conn} do
    instance_id = "layout-rails-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    {:ok, view, _html} =
      live(conn, "/studio/agents/#{slug}/#{instance_id}?node=all&view=advanced")

    assert has_element?(view, ".js-agent-summary-pane")
    assert render(view) =~ "lg:grid-cols-[190px_minmax(0,1fr)_280px]"

    view
    |> element("a[href*='/observe']", "Observe")
    |> render_click()

    assert has_element?(view, ".js-agent-summary-pane")
    assert render(view) =~ "lg:grid-cols-[190px_minmax(0,1fr)_280px]"

    view
    |> element("a[href*='/configure']", "Configure")
    |> render_click()

    assert has_element?(view, ".js-agent-summary-pane")
    assert render(view) =~ "lg:grid-cols-[190px_minmax(0,1fr)_280px]"
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
