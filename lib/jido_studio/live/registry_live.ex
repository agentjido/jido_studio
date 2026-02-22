defmodule JidoStudio.RegistryLive do
  @moduledoc false
  use Phoenix.LiveView

  alias JidoStudio.Cluster.Scope

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, :page_title, "Catalog")}
  end

  @impl true
  def handle_params(_params, uri, socket) do
    query =
      uri
      |> URI.parse()
      |> Map.get(:query)
      |> decode_query()
      |> Enum.reject(fn {_key, value} -> is_nil(value) or value == "" end)
      |> Map.new()

    base = socket.assigns.prefix <> "/catalog"

    target =
      if map_size(query) == 0 do
        base
      else
        base <> "?" <> URI.encode_query(query)
      end

    {:noreply, push_navigate(socket, to: Scope.with_scope_query(target, query["node"]))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-6">
      <div class="text-xs text-js-text-muted">Redirecting to Catalog...</div>
    </div>
    """
  end

  defp decode_query(nil), do: %{}

  defp decode_query(query) when is_binary(query) do
    URI.decode_query(query)
  rescue
    _ -> %{}
  end
end
