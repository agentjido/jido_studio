defmodule JidoStudio.Display do
  @moduledoc false

  def value(value, default \\ "n/a")

  def value(value, default) when value in [nil, ""], do: default
  def value(value, _default) when is_boolean(value), do: to_string(value)
  def value(value, _default) when is_binary(value), do: value
  def value(value, _default) when is_atom(value), do: Atom.to_string(value)
  def value(value, _default) when is_integer(value), do: Integer.to_string(value)
  def value(value, _default) when is_float(value), do: Float.to_string(value)

  def value(value, _default) do
    inspect(value, pretty: true, limit: 120, printable_limit: 20_000)
  end

  def model_label(value, default \\ "n/a")

  def model_label(%{provider: provider, id: id}, _default)
      when (is_atom(provider) or is_binary(provider)) and is_binary(id) do
    compose_model_label(provider, id)
  end

  def model_label(%{"provider" => provider, "id" => id}, _default)
      when (is_atom(provider) or is_binary(provider)) and is_binary(id) do
    compose_model_label(provider, id)
  end

  def model_label(%{id: id}, _default) when is_binary(id), do: id
  def model_label(%{"id" => id}, _default) when is_binary(id), do: id
  def model_label(value, default), do: value(value, default)

  defp compose_model_label(provider, id) do
    provider = provider |> to_string() |> String.trim()
    id = String.trim(id)

    cond do
      provider == "" ->
        id

      String.starts_with?(id, provider <> "/") or String.starts_with?(id, provider <> ":") ->
        id

      true ->
        provider <> ":" <> id
    end
  end
end
