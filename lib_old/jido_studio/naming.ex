defmodule JidoStudio.Naming do
  @moduledoc false

  @acronyms %{
    "api" => "API",
    "ai" => "AI",
    "llm" => "LLM",
    "id" => "ID"
  }

  @spec humanize(String.t() | atom() | nil) :: String.t()
  def humanize(nil), do: "Unknown"

  def humanize(value) when is_atom(value) do
    value
    |> Atom.to_string()
    |> humanize()
  end

  def humanize(value) when is_binary(value) do
    value
    |> String.trim()
    |> String.replace(~r/[-_]+/, " ")
    |> String.replace(~r/\s+/, " ")
    |> String.split(" ", trim: true)
    |> Enum.map_join(" ", &humanize_token/1)
  end

  def humanize(_), do: "Unknown"

  defp humanize_token(token) do
    Map.get(@acronyms, String.downcase(token), String.capitalize(token))
  end
end
