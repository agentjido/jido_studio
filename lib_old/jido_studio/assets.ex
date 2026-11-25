defmodule JidoStudio.Assets do
  @moduledoc false

  @css_path "priv/static/jido_studio.css"
  @js_path "priv/static/jido_studio.js"

  if File.exists?(@css_path) do
    @external_resource @css_path
    @css File.read!(@css_path)
  else
    @css ""
  end

  if File.exists?(@js_path) do
    @external_resource @js_path
    @js File.read!(@js_path)
  else
    @js ""
  end

  @doc false
  def css, do: @css

  @doc false
  def js, do: @js
end
