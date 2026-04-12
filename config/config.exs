import Config

if config_env() == :dev do
  config :git_ops,
    mix_project: JidoStudio.MixProject,
    changelog_file: "CHANGELOG.md",
    repository_url: "https://github.com/agentjido/jido_studio",
    manage_mix_version?: true,
    manage_readme_version: "README.md",
    version_tag_prefix: "v",
    types: [
      feat: [header: "Features"],
      fix: [header: "Bug Fixes"],
      perf: [header: "Performance"],
      refactor: [header: "Refactoring"],
      docs: [hidden?: true],
      test: [hidden?: true],
      deps: [hidden?: true],
      chore: [hidden?: true],
      ci: [hidden?: true]
    ]
end

config :jido_studio,
  trace_preview_limit: 200,
  live_ops: [
    enabled: true,
    auto_follow_default: true,
    scope_keys: [:project_id, :user_id]
  ],
  cluster: [
    enabled: true,
    rpc_timeout_ms: 3_000,
    default_scope: :all
  ],
  branding: [
    about_links: [
      %{label: "Agent Jido", url: "https://agentjido.xyz"},
      %{label: "LLMDB", url: "https://llmdb.xyz"},
      %{label: "GitHub", url: "https://github.com/sagents-ai/jido_studio"},
      %{label: "Community", url: "https://github.com/sagents-ai/jido/discussions"}
    ],
    about_tagline: "Observe, understand, and guide your Agents from one place.",
    support_email: nil,
    docs_url: "https://agentjido.xyz"
  ],
  delegation: [
    enabled: true
  ],
  tracing: [
    hide_internal_default: true,
    chunk_span_sampling: 1.0,
    max_span_rows: 5_000
  ],
  evals: [
    enabled: true,
    rule_sets: [:default]
  ],
  persistence: [
    adapter: JidoStudio.Persistence.ETS,
    opts: []
  ]
