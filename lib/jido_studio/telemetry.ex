defmodule JidoStudio.Telemetry do
  @moduledoc false

  @prefix [:jido_studio]

  @spec execute([atom()], map(), map()) :: :ok
  def execute(event, measurements \\ %{}, metadata \\ %{})
      when is_list(event) and is_map(measurements) and is_map(metadata) do
    :telemetry.execute(@prefix ++ event, measurements, metadata)
  end
end
