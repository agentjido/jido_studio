defmodule JidoStudio.Setup.Profiles do
  @moduledoc false

  @profiles [
    %{
      key: "local_dev",
      label: "Local Dev Fast Start",
      badge: "Profile A",
      summary: "Fast iteration with permissive defaults.",
      snippet: """
      config :jido_studio,
        jido_instance: MyApp.Jido,
        thread_persistence: true,
        thread_storage: {Jido.Storage.ETS, table: :jido_studio_threads},
        live_ops: [enabled: true, viewer_tracking: false]
      """,
      changes: [
        "Keeps setup minimal for a single developer.",
        "Uses ETS-backed thread storage (ephemeral on restart).",
        "Allows polling fallback when realtime presence is unavailable."
      ],
      rollback: "Revert thread storage to file-backed or inherit your runtime storage mode."
    },
    %{
      key: "chat_demo",
      label: "Chat Demo Showcase",
      badge: "Profile B",
      summary: "Optimize for chat walkthroughs and demos.",
      snippet: """
      config :jido_studio,
        jido_instance: MyApp.Jido,
        thread_persistence: true,
        thread_storage: {Jido.Storage.File, path: "priv/jido_studio/storage"},
        live_ops: [enabled: true, viewer_tracking: true]

      # Add at least one provider key:
      # OPENAI_API_KEY=...
      # ANTHROPIC_API_KEY=...
      """,
      changes: [
        "Enables durable thread history for repeatable demos.",
        "Requires chat provider keys for chat-first workflows.",
        "Keeps non-chat Interact flows available as fallback."
      ],
      rollback: "Remove provider keys to return to non-chat mode and switch storage back to ETS."
    },
    %{
      key: "team_durable_ops",
      label: "Team Durable Ops",
      badge: "Profile C",
      summary: "Durability and realtime visibility for shared operations.",
      snippet: """
      config :jido_studio,
        jido_instance: MyApp.Jido,
        thread_persistence: true,
        thread_storage_mode: :studio,
        thread_storage: {Jido.Storage.File, path: "priv/jido_studio/storage"},
        live_ops: [enabled: true, viewer_tracking: true, presence_module: MyApp.Presence],
        tracing: [max_span_rows: 2000]
      """,
      changes: [
        "Targets multi-user operations and incident response.",
        "Uses durable storage with presence-backed realtime updates.",
        "Keeps diagnostics span cap aligned with timeline safeguards."
      ],
      rollback:
        "Disable presence integration or switch thread storage to ETS for lighter local operation."
    }
  ]

  @spec profiles() :: [map()]
  def profiles, do: @profiles

  @spec default_profile_key() :: String.t()
  def default_profile_key, do: "local_dev"

  @spec find_profile(term()) :: map()
  def find_profile(key) do
    key = normalize_key(key)

    Enum.find(@profiles, fn profile ->
      profile.key == key
    end) || hd(@profiles)
  end

  @spec infer_profile(map()) :: String.t()
  def infer_profile(%{
        runtime_ready?: runtime_ready?,
        durable_persistence?: durable_persistence?,
        realtime_event_driven?: realtime_event_driven?,
        chat_keys_present?: chat_keys_present?
      }) do
    cond do
      runtime_ready? and durable_persistence? and realtime_event_driven? ->
        "team_durable_ops"

      runtime_ready? and chat_keys_present? ->
        "chat_demo"

      true ->
        "local_dev"
    end
  end

  def infer_profile(_), do: default_profile_key()

  defp normalize_key(value) when is_binary(value) do
    case String.trim(value) do
      "" -> default_profile_key()
      normalized -> normalized
    end
  end

  defp normalize_key(value) when is_atom(value), do: normalize_key(Atom.to_string(value))
  defp normalize_key(_), do: default_profile_key()
end
