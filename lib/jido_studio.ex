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

  - **Agents** — Browse, inspect, and chat with running agents
  - **Actions** — View registered actions and their schemas
  - **Workflows** — Visualize and debug workflow execution
  - **Signals** — Monitor signal routing and delivery
  - **Traces** — View telemetry events with trace correlation
  - **Settings** — Configure runtime behavior

  ## Customization

  Use a resolver module to control access and customize behavior:

      jido_studio "/studio", resolver: MyApp.StudioResolver

  See `JidoStudio.Resolver` for the full callback specification.

  ## Configuration

      config :jido_studio,
        pubsub: MyApp.PubSub,
        trace_buffer_size: 500
  """

  @doc """
  Returns the current version of Jido Studio.
  """
  @spec version() :: String.t()
  def version do
    "0.1.0"
  end
end
