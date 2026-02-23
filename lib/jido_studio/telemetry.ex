defmodule JidoStudio.Telemetry do
  @moduledoc false

  @prefix [:jido_studio]

  @spec execute([atom()], map(), map()) :: :ok
  def execute(event, measurements \\ %{}, metadata \\ %{})
      when is_list(event) and is_map(measurements) and is_map(metadata) do
    :telemetry.execute(@prefix ++ event, measurements, metadata)
  end

  @spec compact_metadata(map()) :: map()
  def compact_metadata(metadata) when is_map(metadata) do
    Enum.reduce(metadata, %{}, fn
      {_key, nil}, acc ->
        acc

      {key, value}, acc when is_binary(value) ->
        case String.trim(value) do
          "" -> acc
          normalized -> Map.put(acc, key, normalized)
        end

      {key, value}, acc ->
        Map.put(acc, key, value)
    end)
  end
end
