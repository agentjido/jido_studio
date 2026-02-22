defmodule JidoStudio.Agents.ActionCatalog do
  @moduledoc false

  @type action_row :: %{
          key: String.t(),
          kind: :strategy_cmd | :action_module | :custom_target,
          source: [atom()],
          signal_types: [String.t()],
          primary_signal_type: String.t() | nil,
          label: String.t(),
          doc: String.t() | nil,
          action: term(),
          module: module() | nil,
          schema: term(),
          schema_json: map() | nil,
          schema_error: String.t() | nil,
          required_fields: [String.t()],
          convertible_schema?: boolean()
        }

  @spec build(module() | nil, [map()], keyword()) :: %{actions: [action_row()], warnings: [String.t()]}
  def build(agent_module, signals, _opts \\ []) do
    strategy_module = safe_strategy_module(agent_module)

    route_refs =
      signals
      |> List.wrap()
      |> Enum.flat_map(&refs_from_signal_row/1)

    plugin_action_refs = refs_from_plugin_actions(agent_module)

    merged =
      (route_refs ++ plugin_action_refs)
      |> Enum.reduce(%{}, fn ref, acc ->
        key = ref.key

        Map.update(acc, key, ref, fn existing ->
          existing
          |> Map.update(:source, ref.source, fn current ->
            (List.wrap(current) ++ List.wrap(ref.source)) |> Enum.uniq()
          end)
          |> Map.update(:signal_types, ref.signal_types, fn current ->
            (List.wrap(current) ++ List.wrap(ref.signal_types))
            |> Enum.reject(&is_nil/1)
            |> Enum.uniq()
          end)
          |> Map.put_new(:primary_signal_type, ref.primary_signal_type)
        end)
      end)

    {rows, warnings} =
      merged
      |> Map.values()
      |> Enum.map(&enrich_row(&1, strategy_module))
      |> Enum.reduce({[], []}, fn {row, row_warnings}, {rows_acc, warnings_acc} ->
        {rows_acc ++ [row], warnings_acc ++ row_warnings}
      end)

    %{
      actions: Enum.sort_by(rows, &String.downcase(to_string(&1.label || &1.key))),
      warnings: Enum.uniq(warnings)
    }
  end

  defp refs_from_signal_row(%{} = row) do
    signal_type = normalize_signal_type(row[:signal_type] || row["signal_type"])
    source = [row[:source] || row["source"] || :unknown]

    case action_ref_from_target(row[:target] || row["target"]) do
      nil ->
        []

      %{key: key, kind: kind, action: action, module: module, label: label} ->
        [
          %{
            key: key,
            kind: kind,
            action: action,
            module: module,
            label: label,
            source: source,
            signal_types: if(is_binary(signal_type), do: [signal_type], else: []),
            primary_signal_type: signal_type
          }
        ]
    end
  end

  defp refs_from_signal_row(_), do: []

  defp refs_from_plugin_actions(agent_module) when is_atom(agent_module) do
    actions =
      if function_exported?(agent_module, :actions, 0) do
        List.wrap(agent_module.actions())
      else
        []
      end

    Enum.flat_map(actions, fn
      module when is_atom(module) ->
        [
          %{
            key: "module:" <> inspect(module),
            kind: :action_module,
            action: module,
            module: module,
            label: short_module_name(module),
            source: [:plugin],
            signal_types: [],
            primary_signal_type: nil
          }
        ]

      _ ->
        []
    end)
  rescue
    _ -> []
  end

  defp refs_from_plugin_actions(_), do: []

  defp action_ref_from_target(target) when is_atom(target) do
    %{
      key: "module:" <> inspect(target),
      kind: :action_module,
      action: target,
      module: target,
      label: short_module_name(target)
    }
  end

  defp action_ref_from_target({:strategy_cmd, action}) do
    %{
      key: "strategy:" <> inspect(action),
      kind: :strategy_cmd,
      action: action,
      module: nil,
      label: to_string(action)
    }
  end

  defp action_ref_from_target({:custom, action}) do
    %{
      key: "custom:" <> inspect(action),
      kind: :custom_target,
      action: action,
      module: nil,
      label: "custom " <> inspect(action)
    }
  end

  defp action_ref_from_target({module, _opts}) when is_atom(module) do
    action_ref_from_target(module)
  end

  defp action_ref_from_target(_), do: nil

  defp enrich_row(%{kind: :strategy_cmd} = row, strategy_module) do
    spec =
      if is_atom(strategy_module) and function_exported?(strategy_module, :action_spec, 1) do
        strategy_module.action_spec(row.action)
      else
        nil
      end

    name =
      case spec do
        %{name: value} when is_binary(value) -> value
        _ -> row.label || inspect(row.action)
      end

    doc =
      case spec do
        %{doc: value} when is_binary(value) -> value
        _ -> nil
      end

    schema = if is_map(spec), do: spec[:schema], else: nil
    {schema_json, schema_error} = json_schema(schema)

    {
      %{
        key: row.key,
        kind: row.kind,
        source: normalize_sources(row.source),
        signal_types: normalize_signal_types(row.signal_types),
        primary_signal_type: row.primary_signal_type,
        label: name,
        doc: doc,
        action: row.action,
        module: nil,
        schema: schema,
        schema_json: schema_json,
        schema_error: schema_error,
        required_fields: required_fields(schema_json),
        convertible_schema?: is_nil(schema_error)
      },
      warning_messages(schema_error, row.key)
    }
  rescue
    error ->
      {
        fallback_action_row(row, "Failed to resolve strategy action: " <> Exception.message(error)),
        ["Failed to resolve strategy action #{row.key}: " <> Exception.message(error)]
      }
  end

  defp enrich_row(%{kind: :action_module, module: module} = row, _strategy_module) do
    metadata =
      cond do
        is_atom(module) and function_exported?(module, :__action_metadata__, 0) ->
          module.__action_metadata__()

        true ->
          %{}
      end

    schema =
      cond do
        is_map(metadata) and Map.has_key?(metadata, :schema) ->
          metadata[:schema]

        is_atom(module) and function_exported?(module, :schema, 0) ->
          module.schema()

        true ->
          nil
      end

    label =
      cond do
        is_map(metadata) and is_binary(metadata[:name]) -> metadata[:name]
        true -> row.label || short_module_name(module)
      end

    doc =
      cond do
        is_map(metadata) and is_binary(metadata[:description]) -> metadata[:description]
        true -> nil
      end

    {schema_json, schema_error} = json_schema(schema)

    {
      %{
        key: row.key,
        kind: row.kind,
        source: normalize_sources(row.source),
        signal_types: normalize_signal_types(row.signal_types),
        primary_signal_type: row.primary_signal_type,
        label: label,
        doc: doc,
        action: module,
        module: module,
        schema: schema,
        schema_json: schema_json,
        schema_error: schema_error,
        required_fields: required_fields(schema_json),
        convertible_schema?: is_nil(schema_error)
      },
      warning_messages(schema_error, row.key)
    }
  rescue
    error ->
      {
        fallback_action_row(row, "Failed to resolve action metadata: " <> Exception.message(error)),
        ["Failed to resolve action #{row.key}: " <> Exception.message(error)]
      }
  end

  defp enrich_row(row, _strategy_module) do
    {
      %{
        key: row.key,
        kind: :custom_target,
        source: normalize_sources(row.source),
        signal_types: normalize_signal_types(row.signal_types),
        primary_signal_type: row.primary_signal_type,
        label: row.label || inspect(row.action),
        doc: "Custom route target. No schema available.",
        action: row.action,
        module: nil,
        schema: nil,
        schema_json: nil,
        schema_error: nil,
        required_fields: [],
        convertible_schema?: true
      },
      []
    }
  end

  defp warning_messages(nil, _key), do: []
  defp warning_messages(error, key), do: ["Schema conversion failed for #{key}: #{error}"]

  defp fallback_action_row(row, schema_error) do
    %{
      key: row.key,
      kind: row.kind || :custom_target,
      source: normalize_sources(row.source),
      signal_types: normalize_signal_types(row.signal_types),
      primary_signal_type: row.primary_signal_type,
      label: row.label || row.key,
      doc: nil,
      action: row.action,
      module: Map.get(row, :module),
      schema: nil,
      schema_json: nil,
      schema_error: schema_error,
      required_fields: [],
      convertible_schema?: false
    }
  end

  defp safe_strategy_module(agent_module) when is_atom(agent_module) do
    if function_exported?(agent_module, :strategy, 0) do
      agent_module.strategy()
    else
      nil
    end
  rescue
    _ -> nil
  end

  defp safe_strategy_module(_), do: nil

  defp json_schema(nil), do: {nil, nil}

  defp json_schema(schema) do
    try do
      {Jido.Action.Schema.to_json_schema(schema), nil}
    rescue
      error ->
        {nil, Exception.message(error)}
    catch
      kind, reason ->
        {nil, "#{kind}: #{inspect(reason)}"}
    end
  end

  defp normalize_signal_type(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_signal_type(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_signal_type(_), do: nil

  defp normalize_signal_types(values) when is_list(values) do
    values
    |> Enum.map(&normalize_signal_type/1)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp normalize_signal_types(_), do: []

  defp normalize_sources(values) when is_list(values) do
    values
    |> Enum.map(fn
      value when is_atom(value) -> value
      value when is_binary(value) ->
        case value |> String.trim() |> String.downcase() do
          "runtime_router" -> :runtime_router
          "strategy" -> :strategy
          "agent" -> :agent
          "plugin" -> :plugin
          "plugin_schedule" -> :plugin_schedule
          _ -> :unknown
        end

      _ -> :unknown
    end)
    |> Enum.uniq()
  rescue
    _ -> [:unknown]
  end

  defp normalize_sources(_), do: [:unknown]

  defp required_fields(%{"required" => required}) when is_list(required) do
    Enum.map(required, &to_string/1)
  end

  defp required_fields(_), do: []

  defp short_module_name(module) when is_atom(module) do
    module
    |> Module.split()
    |> Enum.join(".")
  end

  defp short_module_name(other), do: inspect(other)
end
