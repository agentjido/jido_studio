defmodule JidoStudio.Agents.PayloadForm do
  @moduledoc false

  @supported_types ~w(string number integer boolean)

  @spec build(map(), {:signal | :action, String.t()} | nil, String.t(), map()) :: map()
  def build(interaction_model, selection, payload_json, field_errors \\ %{})

  def build(interaction_model, selection, payload_json, field_errors)
      when is_map(interaction_model) do
    payload = decode_payload(payload_json)

    case schema_json_for_selection(interaction_model, selection) do
      nil ->
        %{supported?: false, reason: "No schema available for this selection.", fields: []}

      schema_json ->
        case field_definitions(schema_json) do
          {:ok, definitions} ->
            %{
              supported?: true,
              reason: nil,
              fields:
                Enum.map(definitions, fn field ->
                  value = Map.get(payload, field.name)

                  field
                  |> Map.put(:value, input_value(field.type, sanitize_value(value)))
                  |> Map.put(:error, Map.get(field_errors, field.name))
                end)
            }

          {:error, reason} ->
            %{supported?: false, reason: reason, fields: []}
        end
    end
  end

  def build(_, _, _, _), do: %{supported?: false, reason: "No schema available.", fields: []}

  @spec apply_fields(map(), {:signal | :action, String.t()} | nil, map()) ::
          {:ok, String.t(), map()}
  def apply_fields(interaction_model, selection, field_params)
      when is_map(interaction_model) and is_map(field_params) do
    with schema_json when not is_nil(schema_json) <-
           schema_json_for_selection(interaction_model, selection),
         {:ok, fields} <- field_definitions(schema_json) do
      {payload, errors} =
        Enum.reduce(fields, {%{}, %{}}, fn field, {payload_acc, errors_acc} ->
          raw = Map.get(field_params, field.name, "")

          case cast_value(field, raw) do
            {:ok, casted} ->
              {Map.put(payload_acc, field.name, casted), errors_acc}

            {:error, message, fallback} ->
              {
                Map.put(payload_acc, field.name, fallback),
                Map.put(errors_acc, field.name, message)
              }
          end
        end)

      {:ok, Jason.encode!(payload), errors}
    else
      _ -> {:ok, "{}", %{}}
    end
  end

  def apply_fields(_, _, _), do: {:ok, "{}", %{}}

  @spec schema_json_for_selection(map(), {:signal | :action, String.t()} | nil) :: map() | nil
  def schema_json_for_selection(interaction_model, {:action, key}) when is_binary(key) do
    interaction_model[:actions]
    |> List.wrap()
    |> Enum.find(&(&1[:key] == key))
    |> case do
      %{schema_json: schema_json} when is_map(schema_json) -> schema_json
      _ -> nil
    end
  end

  def schema_json_for_selection(interaction_model, {:signal, key}) when is_binary(key) do
    signal =
      interaction_model[:signals]
      |> List.wrap()
      |> Enum.find(&(&1[:key] == key))

    case signal do
      %{signal_type: signal_type} when is_binary(signal_type) ->
        interaction_model[:actions]
        |> List.wrap()
        |> Enum.find(&(&1[:primary_signal_type] == signal_type))
        |> case do
          %{schema_json: schema_json} when is_map(schema_json) -> schema_json
          _ -> nil
        end

      _ ->
        nil
    end
  end

  def schema_json_for_selection(_, _), do: nil

  @spec decode_payload(String.t()) :: map()
  def decode_payload(payload_json) when is_binary(payload_json) do
    case Jason.decode(payload_json) do
      {:ok, %{} = payload} -> payload
      _ -> %{}
    end
  end

  def decode_payload(_), do: %{}

  defp field_definitions(schema_json) when is_map(schema_json) do
    type = Map.get(schema_json, "type") || Map.get(schema_json, :type)
    properties = Map.get(schema_json, "properties") || Map.get(schema_json, :properties) || %{}

    required =
      MapSet.new(Map.get(schema_json, "required") || Map.get(schema_json, :required) || [])

    cond do
      type not in ["object", :object] ->
        {:error, "Complex schema requires raw JSON mode."}

      not is_map(properties) ->
        {:error, "Complex schema requires raw JSON mode."}

      true ->
        fields =
          properties
          |> Enum.map(fn {name, field_schema} ->
            field_type = simple_type(field_schema)

            %{
              name: to_string(name),
              label: humanize_label(name),
              type: field_type,
              required?:
                MapSet.member?(required, name) or MapSet.member?(required, to_string(name)),
              description:
                normalize_description(
                  field_schema[:description] || field_schema["description"] ||
                    field_schema[:title] ||
                    field_schema["title"]
                )
            }
          end)

        if Enum.any?(fields, &(&1.type == :unsupported)) do
          {:error, "Complex schema requires raw JSON mode."}
        else
          {:ok, Enum.sort_by(fields, &String.downcase(&1.name))}
        end
    end
  end

  defp field_definitions(_), do: {:error, "Complex schema requires raw JSON mode."}

  defp simple_type(field_schema) when is_map(field_schema) do
    type = field_schema[:type] || field_schema["type"]

    normalized =
      case type do
        atom when is_atom(atom) -> Atom.to_string(atom)
        binary when is_binary(binary) -> String.downcase(binary)
        _ -> nil
      end

    if normalized in @supported_types do
      String.to_atom(normalized)
    else
      :unsupported
    end
  end

  defp simple_type(_), do: :unsupported

  defp cast_value(%{type: :string}, raw), do: {:ok, to_string(raw || "")}

  defp cast_value(%{type: :boolean} = field, raw) do
    normalized = raw |> to_string() |> String.trim() |> String.downcase()

    cond do
      normalized in ["true", "1", "on", "yes"] ->
        {:ok, true}

      normalized in ["false", "0", "off", "no"] ->
        {:ok, false}

      normalized == "" and not field.required? ->
        {:ok, false}

      true ->
        {:error, "Enter true or false.", normalized}
    end
  end

  defp cast_value(%{type: :number} = field, raw) do
    normalized = raw |> to_string() |> String.trim()

    cond do
      normalized == "" and not field.required? ->
        {:ok, nil}

      normalized == "" ->
        {:error, "Required field.", normalized}

      true ->
        case Float.parse(normalized) do
          {value, ""} -> {:ok, value}
          _ -> {:error, "Enter a valid number.", normalized}
        end
    end
  end

  defp cast_value(%{type: :integer} = field, raw) do
    normalized = raw |> to_string() |> String.trim()

    cond do
      normalized == "" and not field.required? ->
        {:ok, nil}

      normalized == "" ->
        {:error, "Required field.", normalized}

      true ->
        case Integer.parse(normalized) do
          {value, ""} -> {:ok, value}
          _ -> {:error, "Enter a whole number.", normalized}
        end
    end
  end

  defp cast_value(_field, raw), do: {:ok, raw}

  defp sanitize_value("<value>"), do: nil
  defp sanitize_value(value), do: value

  defp input_value(:boolean, true), do: "true"
  defp input_value(:boolean, false), do: "false"

  defp input_value(:number, value) when is_float(value),
    do:
      :erlang.float_to_binary(value, decimals: 6)
      |> String.trim_trailing("0")
      |> String.trim_trailing(".")

  defp input_value(:number, value) when is_integer(value), do: Integer.to_string(value)
  defp input_value(:integer, value) when is_integer(value), do: Integer.to_string(value)
  defp input_value(_type, value) when is_binary(value), do: value
  defp input_value(_type, nil), do: ""
  defp input_value(_type, value), do: to_string(value)

  defp normalize_description(value) when is_binary(value) do
    normalized =
      value
      |> String.trim()
      |> String.trim_trailing(".")
      |> String.downcase()

    if normalized in ["", "no description provided"], do: nil, else: String.trim(value)
  end

  defp normalize_description(_), do: nil

  defp humanize_label(value) when is_atom(value),
    do: value |> Atom.to_string() |> humanize_label()

  defp humanize_label(value) when is_binary(value) do
    value
    |> String.replace("_", " ")
    |> String.split(".")
    |> List.last()
    |> String.capitalize()
  end

  defp humanize_label(_), do: "Field"
end
