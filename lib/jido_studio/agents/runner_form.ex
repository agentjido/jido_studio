defmodule JidoStudio.Agents.RunnerForm do
  @moduledoc false

  @dispatch_modes ~w(sync async)
  @schema_modes ~w(fields raw)

  @type t :: %__MODULE__{
          selected_signal_key: String.t() | nil,
          selected_action_key: String.t() | nil,
          dispatch_mode: String.t(),
          payload_json: String.t(),
          schema_mode: String.t(),
          guard_armed?: boolean(),
          guard_hash: integer() | nil
        }

  defstruct selected_signal_key: nil,
            selected_action_key: nil,
            dispatch_mode: "sync",
            payload_json: "{}",
            schema_mode: "fields",
            guard_armed?: false,
            guard_hash: nil

  @spec new(map() | keyword()) :: t()
  def new(overrides \\ %{}) do
    %__MODULE__{}
    |> Map.from_struct()
    |> Map.merge(normalize_map(overrides))
    |> normalize()
  end

  @spec parse(map() | keyword() | nil, t() | nil) :: t()
  def parse(params, defaults \\ %__MODULE__{})

  def parse(nil, %__MODULE__{} = defaults), do: defaults

  def parse(params, %__MODULE__{} = defaults) do
    source = normalize_map(params["runner"] || params)

    defaults
    |> Map.from_struct()
    |> Map.merge(%{
      dispatch_mode: source["dispatch_mode"] || source[:dispatch_mode] || defaults.dispatch_mode,
      payload_json: source["payload_json"] || source[:payload_json] || defaults.payload_json,
      schema_mode: source["schema_mode"] || source[:schema_mode] || defaults.schema_mode
    })
    |> normalize()
    |> maybe_reset_guard(defaults)
  end

  def parse(_params, defaults), do: parse(nil, defaults || %__MODULE__{})

  @spec select_signal(t(), String.t() | nil) :: t()
  def select_signal(%__MODULE__{} = form, key) do
    normalized = normalize_optional_string(key)
    %{form | selected_signal_key: normalized, selected_action_key: nil}
    |> disarm()
  end

  @spec select_action(t(), String.t() | nil) :: t()
  def select_action(%__MODULE__{} = form, key) do
    normalized = normalize_optional_string(key)
    %{form | selected_signal_key: nil, selected_action_key: normalized}
    |> disarm()
  end

  @spec arm(t()) :: t()
  def arm(%__MODULE__{} = form) do
    %{form | guard_armed?: true, guard_hash: payload_hash(form)}
  end

  @spec disarm(t()) :: t()
  def disarm(%__MODULE__{} = form) do
    %{form | guard_armed?: false, guard_hash: nil}
  end

  @spec payload_hash(t()) :: integer()
  def payload_hash(%__MODULE__{} = form) do
    :erlang.phash2(normalize_payload_json(form.payload_json))
  end

  @spec selected_target(t()) :: {:signal, String.t()} | {:action, String.t()} | nil
  def selected_target(%__MODULE__{selected_signal_key: key}) when is_binary(key),
    do: {:signal, key}

  def selected_target(%__MODULE__{selected_action_key: key}) when is_binary(key),
    do: {:action, key}

  def selected_target(_), do: nil

  @spec can_execute?(t()) :: boolean()
  def can_execute?(%__MODULE__{} = form) do
    match?({_, _}, selected_target(form)) and form.guard_armed? and form.guard_hash == payload_hash(form)
  end

  defp normalize(data) when is_map(data) do
    %__MODULE__{
      selected_signal_key:
        normalize_optional_string(data[:selected_signal_key] || data["selected_signal_key"]),
      selected_action_key:
        normalize_optional_string(data[:selected_action_key] || data["selected_action_key"]),
      dispatch_mode: normalize_enum(data[:dispatch_mode] || data["dispatch_mode"], @dispatch_modes, "sync"),
      payload_json: normalize_payload_json(data[:payload_json] || data["payload_json"]),
      schema_mode: normalize_enum(data[:schema_mode] || data["schema_mode"], @schema_modes, "fields"),
      guard_armed?: data[:guard_armed?] == true or data["guard_armed?"] == true,
      guard_hash: normalize_optional_integer(data[:guard_hash] || data["guard_hash"])
    }
  end

  defp normalize(_), do: %__MODULE__{}

  defp maybe_reset_guard(%__MODULE__{} = parsed, %__MODULE__{} = previous) do
    if payload_hash(parsed) != payload_hash(previous) do
      disarm(parsed)
    else
      parsed
    end
  end

  defp normalize_enum(value, allowed, default) when is_binary(value) do
    normalized = value |> String.trim() |> String.downcase()
    if normalized in allowed, do: normalized, else: default
  end

  defp normalize_enum(value, allowed, default) when is_atom(value) do
    normalize_enum(Atom.to_string(value), allowed, default)
  end

  defp normalize_enum(_value, _allowed, default), do: default

  defp normalize_payload_json(value) when is_binary(value) do
    case String.trim(value) do
      "" -> "{}"
      normalized -> normalized
    end
  end

  defp normalize_payload_json(value) when is_map(value) do
    Jason.encode!(value)
  rescue
    _ -> "{}"
  end

  defp normalize_payload_json(_), do: "{}"

  defp normalize_optional_string(nil), do: nil

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_optional_string(_), do: nil

  defp normalize_optional_integer(value) when is_integer(value), do: value

  defp normalize_optional_integer(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {parsed, _} -> parsed
      _ -> nil
    end
  end

  defp normalize_optional_integer(_), do: nil

  defp normalize_map(source) when is_map(source), do: source
  defp normalize_map(source) when is_list(source), do: Map.new(source)
  defp normalize_map(_), do: %{}
end
