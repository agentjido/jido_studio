defmodule JidoStudio.MixProject do
  use Mix.Project

  @version "1.0.0"
  @source_url "https://github.com/agentjido/jido_studio"
  @description "Embeddable agent studio for Jido - a standalone LiveView dashboard for managing and debugging AI agents"

  def project do
    [
      app: :jido_studio,
      version: @version,
      elixir: "~> 1.18",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      name: "Jido Studio",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      aliases: aliases(),
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt",
        plt_add_apps: [:mix]
      ]
    ]
  end

  def application do
    [mod: {JidoStudio.Application, []}, extra_applications: [:logger]]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:phoenix_live_view, "~> 1.0"},
      {:jido, "~> 3.0.0-beta.3", optional: true},

      # Dev & Test
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:git_ops, "~> 2.9", only: :dev, runtime: false},
      {:mix_test_watch, "~> 1.0", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      files: [
        "lib",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "LICENSE"
      ],
      maintainers: ["Mike Hostetler"],
      licenses: ["Apache-2.0"],
      links: %{
        "Documentation" => "https://hexdocs.pm/jido_studio",
        "GitHub" => @source_url,
        "Website" => "https://agentjido.xyz"
      }
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @source_url,
      extras: [
        {"README.md", title: "Home"},
        {"CHANGELOG.md", title: "Changelog"},
        {"LICENSE", title: "License"}
      ]
    ]
  end

  defp aliases do
    [
      q: ["quality"],
      quality: [
        "format --check-formatted",
        "compile --warnings-as-errors",
        "credo --min-priority higher",
        "dialyzer"
      ]
    ]
  end
end
