defmodule JidoStudio.RuntimeScope do
  @moduledoc false

  @default_runtime_key "default"
  @process_runtime_key {__MODULE__, :runtime_key}

  @type runtime_option :: %{
          key: String.t(),
          module: module(),
          label: String.t()
        }

  @spec runtime_options(module() | nil) :: [runtime_option()]
  def runtime_options(default_instance \\ nil) do
    case multi_runtime_options() do
      [] ->
        single_runtime_options(
          default_instance || Application.get_env(:jido_studio, :jido_instance)
        )

      options ->
        options
    end
  end

  @spec default_runtime_key([runtime_option()]) :: String.t() | nil
  def default_runtime_key([%{key: key} | _]) when is_binary(key), do: key
  def default_runtime_key(_), do: nil

  @spec normalize_runtime_key(term(), [runtime_option()]) :: String.t() | nil
  def normalize_runtime_key(runtime_key, options) when is_list(options) do
    normalized = normalize_optional_string(runtime_key)

    if runtime_key_valid?(normalized, options) do
      normalized
    else
      default_runtime_key(options)
    end
  end

  def normalize_runtime_key(_runtime_key, _options), do: nil

  @spec runtime_module_for_key([runtime_option()], term()) :: module() | nil
  def runtime_module_for_key(options, runtime_key) when is_list(options) do
    selected_key = normalize_runtime_key(runtime_key, options)

    Enum.find_value(options, fn
      %{key: ^selected_key, module: module} when is_atom(module) -> module
      _ -> nil
    end)
  end

  def runtime_module_for_key(_options, _runtime_key), do: nil

  @spec runtime_label_for_key([runtime_option()], term()) :: String.t() | nil
  def runtime_label_for_key(options, runtime_key) when is_list(options) do
    selected_key = normalize_runtime_key(runtime_key, options)

    Enum.find_value(options, fn
      %{key: ^selected_key, label: label} when is_binary(label) -> label
      _ -> nil
    end)
  end

  def runtime_label_for_key(_options, _runtime_key), do: nil

  @spec runtime_warning(term(), term(), [runtime_option()]) :: String.t() | nil
  def runtime_warning(requested_key, selected_key, options) when is_list(options) do
    requested = normalize_optional_string(requested_key)
    selected = normalize_optional_string(selected_key)

    cond do
      requested in [nil, "", selected] ->
        nil

      selected && runtime_key_valid?(selected, options) ->
        selected_label = runtime_label_for_key(options, selected) || selected
        "Selected runtime #{requested} is unavailable. Using #{selected_label}."

      true ->
        "Selected runtime #{requested} is unavailable."
    end
  end

  def runtime_warning(_requested_key, _selected_key, _options), do: nil

  @spec put_process_runtime_key(term(), [runtime_option()]) :: :ok
  def put_process_runtime_key(runtime_key, options \\ runtime_options()) do
    normalized = normalize_optional_string(runtime_key)

    key =
      if normalized in [nil, ""] do
        nil
      else
        normalize_runtime_key(normalized, options)
      end

    Process.put(@process_runtime_key, key)
    :ok
  end

  @spec current_runtime_key([runtime_option()] | nil) :: String.t() | nil
  def current_runtime_key(options \\ nil) do
    case Process.get(@process_runtime_key) do
      nil ->
        nil

      value ->
        if is_list(options) and options != [] do
          normalize_runtime_key(value, options)
        else
          normalize_optional_string(value)
        end
    end
  end

  defp multi_runtime_options do
    :jido_studio
    |> Application.get_env(:jido_instances, [])
    |> normalize_runtime_options()
  end

  defp normalize_runtime_options(options) when is_list(options) do
    options
    |> Enum.flat_map(&normalize_runtime_option/1)
    |> Enum.uniq_by(& &1.key)
  end

  defp normalize_runtime_options(_), do: []

  defp normalize_runtime_option(option) when is_map(option) do
    key = normalize_optional_string(Map.get(option, :key) || Map.get(option, "key"))
    module = Map.get(option, :module) || Map.get(option, "module")
    label = normalize_optional_string(Map.get(option, :label) || Map.get(option, "label"))

    with key when is_binary(key) <- key,
         true <- is_atom(module) do
      [
        %{
          key: key,
          module: module,
          label: label || humanize_key(key)
        }
      ]
    else
      _ -> []
    end
  end

  defp normalize_runtime_option(_), do: []

  defp single_runtime_options(module) when is_atom(module) do
    [
      %{
        key: @default_runtime_key,
        module: module,
        label: default_runtime_label(module)
      }
    ]
  end

  defp single_runtime_options(_), do: []

  defp runtime_key_valid?(nil, _options), do: false

  defp runtime_key_valid?(runtime_key, options) do
    Enum.any?(options, fn
      %{key: ^runtime_key} -> true
      _ -> false
    end)
  end

  defp default_runtime_label(module) when is_atom(module) do
    module
    |> Atom.to_string()
    |> String.split(".")
    |> List.last()
  end

  defp humanize_key(key) when is_binary(key) do
    key
    |> String.replace("_", " ")
    |> String.split()
    |> Enum.map_join(" ", &capitalize/1)
  end

  defp capitalize(""), do: ""

  defp capitalize(value) do
    value
    |> String.downcase()
    |> String.capitalize()
  end

  defp normalize_optional_string(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_optional_string(nil), do: nil
  defp normalize_optional_string(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_optional_string(_), do: nil
end
