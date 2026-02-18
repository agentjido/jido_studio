import Config

config :jido_studio,
  trace_preview_limit: 200,
  live_ops: [
    enabled: true,
    auto_follow_default: true,
    scope_keys: [:project_id, :user_id]
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
