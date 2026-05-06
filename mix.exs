defmodule JidoStudio.MixProject do
  use Mix.Project

  @version "0.1.0"
  @source_url "https://github.com/agentjido/jido_studio"
  @description "Embeddable agent studio for Jido - a standalone LiveView dashboard for managing and debugging AI agents"

  def project do
    [
      app: :jido_studio,
      version: @version,
      elixir: "~> 1.18",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      name: "Jido Studio",
      description: @description,
      source_url: @source_url,
      homepage_url: @source_url,
      package: package(),
      docs: docs(),
      cli: cli(),
      dialyzer: [
        plt_local_path: "priv/plts/project.plt",
        plt_core_path: "priv/plts/core.plt",
        plt_add_apps: [:mix],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {JidoStudio.Application, []}
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:jido, "~> 2.1.0"},
      {:jido_ai, "~> 2.0.0"},
      {:phoenix, "~> 1.7"},
      {:phoenix_html, "~> 4.0"},
      {:phoenix_live_view, "~> 1.0"},
      {:phoenix_pubsub, "~> 2.1"},
      {:jason, "~> 1.4"},
      {:mdex, "~> 0.11.3"},
      {:telemetry_metrics, "~> 1.0"},
      {:lucide_icons, "~> 2.0"},

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
        "priv/static",
        "priv/ecto",
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
      ],
      "assets.build": ["cmd npm run build:css"]
    ]
  end

  def cli do
    [
      preferred_envs: [
        "jido_studio.benchmark.triage": :test
      ]
    ]
  end
end
