defmodule JidoStudio.AgentsInstanceRoutesTest do
  use JidoStudio.ConnCase, async: false

  alias JidoStudio.AgentRegistry
  alias JidoStudio.PathSegments
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

  test "base instance route remains compatible and defaults to basic view", %{conn: conn} do
    instance_id = "route-base-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    {:ok, view, _html} = live(conn, "/studio/agents/#{slug}/#{instance_id}?node=all")

    assert render(view) =~ "Basic View"
    assert render(view) =~ "2. Set Inputs and Run"
    assert has_element?(view, "a[href*='view=advanced']", "Advanced View")
  end

  test "explicit observe route opens requested observe panel", %{conn: conn} do
    instance_id = "route-observe-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    {:ok, view, _html} =
      live(conn, "/studio/agents/#{slug}/#{instance_id}/observe?panel=thread_context&node=all")

    assert has_element?(view, ".js-instance-menu-section.is-active", "Observe")
    assert has_element?(view, ".js-instance-menu-tab.is-active", "Thread Context")
  end

  test "sharable configure URL restores configure panel and keeps scope query", %{conn: conn} do
    instance_id = "route-configure-#{System.unique_integer([:positive])}"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)

    {:ok, view, _html} =
      live(conn, "/studio/agents/#{slug}/#{instance_id}/configure?panel=middleware&node=all")

    assert has_element?(view, ".js-instance-menu-section.is-active", "Configure")
    assert has_element?(view, ".js-instance-menu-tab.is-active", "Middleware")
    assert has_element?(view, "a[href*='/play'][href*='node=all']")
    assert has_element?(view, "a[href*='/observe'][href*='node=all']")
  end

  test "slash-bearing instance ids use path-safe routes", %{conn: conn} do
    instance_id = "configured_agent_1/react_worker"

    assert {:ok, _pid} =
             Jido.start_agent(TestJido, Jido.AI.Examples.CalculatorAgent, id: instance_id)

    slug = slug_for_module(Jido.AI.Examples.CalculatorAgent)
    encoded_instance_id = PathSegments.encode(instance_id)

    refute encoded_instance_id =~ "/"
    refute encoded_instance_id =~ "%2F"

    {:ok, _view, html} = live(conn, "/studio/agents")

    assert html =~ "/studio/agents/#{slug}/#{encoded_instance_id}/play"

    {:ok, view, _html} =
      live(conn, "/studio/agents/#{slug}/#{encoded_instance_id}/play?node=all")

    assert render(view) =~ "Basic View"
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
