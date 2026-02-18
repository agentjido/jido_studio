defmodule JidoStudio.Messaging do
  @moduledoc """
  Runtime adapter for optional jido_messaging integration.
  """

  @type room :: %{
          required(:id) => String.t(),
          required(:name) => String.t(),
          required(:status) => String.t() | nil,
          required(:topic) => String.t() | nil,
          required(:member_count) => non_neg_integer() | nil,
          required(:raw) => term()
        }

  @type provider :: {module(), atom()}

  @known_root_modules [
    "JidoMessaging",
    "Jido.Messaging"
  ]

  @default_room_providers [
    {"JidoMessaging.Rooms", :list},
    {"JidoMessaging.Rooms", :list_rooms},
    {"JidoMessaging", :list_rooms},
    {"Jido.Messaging", :list_rooms}
  ]

  @doc """
  Returns whether messaging integration appears to be available.
  """
  @spec available?() :: boolean()
  def available? do
    package_available?() or provider_available?()
  end

  @doc """
  Returns whether jido_messaging appears to be present in the project.
  """
  @spec package_available?() :: boolean()
  def package_available? do
    package_loaded?() or default_provider_available?()
  end

  @doc """
  Lists rooms via the first available provider function.
  """
  @spec list_rooms() :: {:ok, [room()]} | {:error, term()}
  def list_rooms do
    with {:ok, provider} <- resolve_provider(),
         {:ok, rooms} <- call_provider(provider) do
      {:ok, Enum.map(List.wrap(rooms), &normalize_room/1)}
    end
  end

  @doc false
  @spec provider_available?() :: boolean()
  def provider_available? do
    case resolve_provider() do
      {:ok, _provider} -> true
      _ -> false
    end
  end

  defp resolve_provider do
    providers()
    |> Enum.find(&provider_defined?/1)
    |> case do
      nil -> {:error, :unavailable}
      provider -> {:ok, provider}
    end
  end

  defp providers do
    configured_providers() ++ default_providers()
  end

  defp configured_providers do
    case Application.get_env(:jido_studio, :messaging_room_provider) do
      {module, function} when is_atom(module) and is_atom(function) ->
        [{module, function}]

      _ ->
        []
    end
  end

  defp default_providers do
    Enum.map(@default_room_providers, fn {module_name, function} ->
      {module_from_string(module_name), function}
    end)
  end

  defp default_provider_available? do
    default_providers()
    |> Enum.any?(&provider_defined?/1)
  end

  defp provider_defined?({module, function}) do
    Code.ensure_loaded?(module) and function_exported?(module, function, 0)
  end

  defp call_provider({module, function}) do
    case apply(module, function, []) do
      {:ok, rooms} when is_list(rooms) -> {:ok, rooms}
      {:ok, other} -> {:ok, List.wrap(other)}
      rooms when is_list(rooms) -> {:ok, rooms}
      nil -> {:ok, []}
      other -> {:error, {:unexpected_result, other}}
    end
  rescue
    error -> {:error, error}
  catch
    kind, reason -> {:error, {kind, reason}}
  end

  defp package_loaded? do
    Enum.any?(@known_root_modules, fn module_name ->
      module_name
      |> module_from_string()
      |> Code.ensure_loaded?()
    end)
  end

  defp module_from_string(module_name) do
    module_name
    |> String.split(".")
    |> Module.concat()
  end

  defp normalize_room(room) do
    map = room_to_map(room)

    id =
      string_field(map, [:id, "id", :room_id, "room_id", :slug, "slug", :name, "name"]) ||
        "room-#{:erlang.phash2(room)}"

    name = string_field(map, [:name, "name", :slug, "slug", :topic, "topic"]) || id

    %{
      id: id,
      name: name,
      status: string_field(map, [:status, "status", :state, "state"]),
      topic: string_field(map, [:topic, "topic"]),
      member_count: member_count(map),
      raw: room
    }
  end

  defp room_to_map(%{} = room) do
    if Map.has_key?(room, :__struct__) do
      Map.from_struct(room)
    else
      room
    end
  end

  defp room_to_map(other), do: %{value: other}

  defp string_field(map, [key | rest]) do
    case Map.get(map, key) do
      nil -> string_field(map, rest)
      value -> normalize_string(value)
    end
  end

  defp string_field(_map, []), do: nil

  defp normalize_string(value) when is_binary(value) do
    trimmed = String.trim(value)
    if trimmed == "", do: nil, else: trimmed
  end

  defp normalize_string(value) when is_atom(value),
    do: value |> Atom.to_string() |> normalize_string()

  defp normalize_string(value) when is_integer(value), do: Integer.to_string(value)
  defp normalize_string(value) when is_float(value), do: Float.to_string(value)
  defp normalize_string(_), do: nil

  defp member_count(map) do
    cond do
      is_integer(map[:member_count]) and map[:member_count] >= 0 ->
        map[:member_count]

      is_integer(map["member_count"]) and map["member_count"] >= 0 ->
        map["member_count"]

      is_list(map[:members]) ->
        length(map[:members])

      is_list(map["members"]) ->
        length(map["members"])

      true ->
        nil
    end
  end
end
