import Config

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
