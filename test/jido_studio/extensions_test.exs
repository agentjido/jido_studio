defmodule JidoStudio.ExtensionsTest do
  use ExUnit.Case, async: true

  alias JidoStudio.Extensions

  defmodule EnabledExtension do
    @behaviour JidoStudio.Extension

    @impl true
    def id, do: :enabled

    @impl true
    def installed?, do: true

    @impl true
    def routes do
      [%{path: "/enabled", live_view: JidoStudio.SettingsLive, action: :index}]
    end

    @impl true
    def nav_sections do
      [
        %{
          id: :enabled,
          label: "Enabled",
          items: [%{path: "/enabled", label: "Enabled", icon: "settings"}]
        }
      ]
    end
  end

  defmodule DisabledExtension do
    @behaviour JidoStudio.Extension

    @impl true
    def id, do: :disabled

    @impl true
    def installed?, do: false

    @impl true
    def routes do
      [%{path: "/disabled", live_view: JidoStudio.SettingsLive, action: :index}]
    end

    @impl true
    def nav_sections do
      [
        %{
          id: :disabled,
          label: "Disabled",
          items: [%{path: "/disabled", label: "Disabled", icon: "settings"}]
        }
      ]
    end
  end

  defmodule InvalidExtension do
    @behaviour JidoStudio.Extension

    @impl true
    def id, do: :invalid

    @impl true
    def installed?, do: true

    @impl true
    def routes do
      [%{path: nil, live_view: nil, action: nil}]
    end

    @impl true
    def nav_sections do
      [%{id: nil, label: nil, items: [%{path: nil, label: nil, icon: nil}]}]
    end
  end

  test "includes active extension routes and excludes inactive ones" do
    routes = Extensions.routes([EnabledExtension, DisabledExtension, InvalidExtension])

    assert Enum.any?(routes, fn route ->
             route.path == "/enabled" and route.live_view == JidoStudio.SettingsLive and
               route.action == :index
           end)

    refute Enum.any?(routes, &(&1.path == "/disabled"))
  end

  test "includes valid active extension nav sections only" do
    sections = Extensions.nav_sections([EnabledExtension, DisabledExtension, InvalidExtension])

    assert Enum.any?(sections, fn section ->
             first_item = List.first(section.items)

             section.id == :enabled and section.label == "Enabled" and
               is_map(first_item) and first_item.path == "/enabled"
           end)

    refute Enum.any?(sections, &(&1.id == :disabled))
  end
end
