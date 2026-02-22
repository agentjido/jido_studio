defmodule JidoStudio do
  @moduledoc """
  Jido Studio - an embeddable agent studio for Phoenix applications.

  Jido Studio provides a full-featured, standalone LiveView UI for managing,
  debugging, and interacting with Jido AI agents. It mounts directly into
  your Phoenix router with a single line — no asset pipeline integration required.

  ## Installation

  Add to your `mix.exs`:

      {:jido_studio, "~> 0.1.0"}

  ## Quick Start

  Mount the studio in your Phoenix router:

      # lib/my_app_web/router.ex
      import JidoStudio.Router

      scope "/" do
        pipe_through [:browser, :require_authenticated_user]
        jido_studio "/studio"
      end

  Start your server and visit `/studio`.

  ## Features

  - **Home** — Fleet health summary with attention cues and quick actions
  - **Agents** — Browse, inspect, and interact with running agents
  - **Catalog** — Discovery-powered catalog of agents, actions, sensors, and plugins
  - **Activity** — Operational timeline across signals, actions, workflows, and traces
  - **Diagnostics** — Deep runtime and cluster health diagnostics
  - **Dual Interaction Surface** — Chat-first UX with non-chat `Interact` introspection/runner support
  - **Live Ops** — Event-driven runtime updates and scoped debugging
  - **Delegation** — Sub-agent/task visibility for causal debugging
  - **Threads** — Inspect persisted thread/memory entries
  - **Traces** — View telemetry events with filtering, critical path, and eval history
  - **Settings** — Configure runtime behavior
  - **About** — Product links, docs, and support information

  ## Customization

  Use a resolver module to control access and customize behavior:

      jido_studio "/studio", resolver: MyApp.StudioResolver

  See `JidoStudio.Resolver` for the full callback specification.

  ## Configuration

      config :jido_studio,
        pubsub: MyApp.PubSub,
        auto_start_runtime: true,
        thread_persistence: true,
        thread_storage: {Jido.Storage.File, path: "priv/jido_studio/storage"},
        thread_storage_mode: :studio,
        thread_retention_days: 30,
        persist_strategy_context: :summary,
        trace_buffer_size: 5000,
        trace_preview_limit: 200,
        trace_page_limit: 300,
        trace_include_agent_debug: true,
        live_ops: [
          enabled: true,
          auto_follow_default: true,
          scope_keys: [:project_id, :user_id],
          event_stream_limit: 100,
          agent_list_poll_ms: 2_000,
          viewer_tracking: true
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
        agent_interactions: [
          enabled: true,
          default_tab: :auto,
          runner_timeout_ms: 5_000,
          runner_history_limit: 20,
          internal_agent_tags: ["internal"]
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
        ],
        trace_events: JidoStudio.TraceCatalog.default_events(),
        presenter_registry: %{
          MyApp.CustomAgent => MyApp.StudioPresenters.CustomAgent
        }
  """

  @doc """
  Returns the current version of Jido Studio.
  """
  @spec version() :: String.t()
  def version do
    "0.1.0"
  end
end
