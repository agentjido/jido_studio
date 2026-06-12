defmodule JidoStudio.Setup.Helpers do
  @moduledoc false

  alias JidoStudio.Setup
  alias JidoStudio.Setup.Profiles
  alias JidoStudio.Telemetry
  alias JidoStudio.Threads.Storage, as: ThreadsStorage

  @spec normalize_profile_key(term(), String.t()) :: String.t()
  def normalize_profile_key(nil, fallback), do: fallback

  def normalize_profile_key(value, fallback) when is_binary(value) do
    case String.trim(value) do
      "" -> fallback
      normalized -> Profiles.find_profile(normalized).key
    end
  end

  def normalize_profile_key(_value, fallback), do: fallback

  @spec emit_step_telemetry(map(), [map()], keyword()) :: :ok
  def emit_step_telemetry(previous_statuses, checks, opts \\ [])
      when is_map(previous_statuses) and is_list(checks) and is_list(opts) do
    runtime = Keyword.get(opts, :runtime)
    node = Keyword.get(opts, :node)
    source = Keyword.get(opts, :source)

    Enum.each(checks, fn check ->
      status = Setup.status_key(check.status)

      if Map.get(previous_statuses, check.id) != status do
        Telemetry.execute([:setup, :step_evaluated], %{count: 1}, %{
          step: to_string(check.id),
          status: status,
          runtime: runtime,
          node: node,
          source: source
        })
      end
    end)

    :ok
  end

  @spec select_profile(term(), keyword()) :: map()
  def select_profile(profile_key, opts \\ []) do
    profile = Profiles.find_profile(profile_key)

    Telemetry.execute([:setup, :profile_selected], %{count: 1}, %{
      profile: profile.key,
      runtime: Keyword.get(opts, :runtime),
      node: Keyword.get(opts, :node),
      source: Keyword.get(opts, :source)
    })

    profile
  end

  @spec thread_storage_details(module() | nil) :: %{adapter: String.t(), path: String.t()}
  def thread_storage_details(jido_instance) do
    case ThreadsStorage.resolve_storage(jido_instance: jido_instance) do
      {:ok, {adapter, opts}} ->
        %{
          adapter: inspect(adapter),
          path: storage_path(opts)
        }

      {:error, _reason} ->
        %{
          adapter: "unavailable",
          path: "n/a"
        }
    end
  rescue
    _ ->
      %{
        adapter: "unavailable",
        path: "n/a"
      }
  end

  defp storage_path(opts) when is_list(opts) do
    opts
    |> Keyword.get(:path)
    |> case do
      value when is_binary(value) and value != "" -> value
      _ -> "n/a"
    end
  end
end
