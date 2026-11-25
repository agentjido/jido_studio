defmodule JidoStudio.PathSegments do
  @moduledoc false

  @opaque_prefix "b64-"

  def encode(value) when is_binary(value) do
    if String.contains?(value, "/") do
      @opaque_prefix <> Base.url_encode64(value, padding: false)
    else
      URI.encode(value, &URI.char_unreserved?/1)
    end
  end

  def encode(value), do: value

  def decode(value) when is_binary(value) do
    if String.starts_with?(value, @opaque_prefix) do
      value
      |> String.replace_prefix(@opaque_prefix, "")
      |> Base.url_decode64(padding: false)
      |> case do
        {:ok, decoded} -> decoded
        :error -> URI.decode(value)
      end
    else
      URI.decode(value)
    end
  end

  def decode(value), do: value
end
