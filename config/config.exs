import Config

config :jido_studio,
  trace_preview_limit: 200,
  persistence: [
    adapter: JidoStudio.Persistence.ETS,
    opts: []
  ]
