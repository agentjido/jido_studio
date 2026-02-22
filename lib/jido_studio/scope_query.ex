defmodule JidoStudio.ScopeQuery do
  @moduledoc false

  alias JidoStudio.Cluster.Scope

  @spec with_scope_query(String.t(), String.t() | nil, String.t() | nil) :: String.t()
  def with_scope_query(path, runtime_key, node_param) when is_binary(path) do
    uri = URI.parse(path)

    params =
      uri.query
      |> decode_query()
      |> maybe_put_runtime(runtime_key)
      |> Map.put("node", Scope.normalize_node_param(node_param))

    uri
    |> Map.put(:query, URI.encode_query(params))
    |> URI.to_string()
  end

  def with_scope_query(path, _runtime_key, _node_param), do: path

  defp maybe_put_runtime(params, runtime_key) do
    case normalize_runtime_key(runtime_key) do
      nil -> Map.delete(params, "runtime")
      value -> Map.put(params, "runtime", value)
    end
  end

  defp decode_query(nil), do: %{}

  defp decode_query(query) when is_binary(query) do
    URI.decode_query(query)
  rescue
    _ -> %{}
  end

  defp normalize_runtime_key(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      normalized -> normalized
    end
  end

  defp normalize_runtime_key(_), do: nil
end
