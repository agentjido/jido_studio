defmodule JidoStudio.Mount do
  @moduledoc false

  import Phoenix.Component, only: [assign: 2, assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, redirect: 2]

  @scope_keys ~w(runtime node)

  def runtime(jido, partition)
      when is_atom(jido) and jido not in [true, false] and
             (is_nil(partition) or (is_binary(partition) and byte_size(partition) > 0)) do
    %{jido: jido, partition: partition}
  end

  def runtime(_jido, _partition) do
    raise ArgumentError, "Studio expects a Jido runtime name and an optional nonempty partition"
  end

  def session(conn, mount_path, nonce_key, showcase?, runtime) do
    router = Phoenix.Controller.router_module(conn)

    %{
      "studio_path" => Phoenix.VerifiedRoutes.unverified_path(conn, router, mount_path),
      "studio_nonces" => %{
        style: nonce(conn, nonce_key, :style),
        script: nonce(conn, nonce_key, :script)
      },
      "studio_showcase" => showcase?,
      "studio_runtime" => runtime
    }
  end

  def on_mount(:default, _params, session, socket) do
    case JidoStudio.Access.level(socket) do
      {:forbidden, path} ->
        {:halt, redirect(socket, to: path)}

      _allowed ->
        socket =
          socket
          |> assign(
            studio_path: session["studio_path"],
            studio_nonces: session["studio_nonces"],
            studio_showcase: session["studio_showcase"],
            studio_runtime: session["studio_runtime"]
          )
          |> attach_hook(:studio_scope, :handle_params, &assign_scope/3)

        {:cont, socket}
    end
  end

  def path(mount_path, relative_path, query) do
    path = String.trim_trailing(mount_path, "/") <> relative_path
    path = if path == "", do: "/", else: path
    if map_size(query) == 0, do: path, else: path <> "?" <> URI.encode_query(query)
  end

  def agent_path(mount, id, scope), do: path(mount, agent_route(id), scope)
  def turns_path(mount, id, scope), do: path(mount, agent_route(id) <> "/turns", scope)

  def decode_agent_id("~" <> id) when id in [".", ".."], do: id
  def decode_agent_id("~~" <> rest), do: "~" <> rest
  def decode_agent_id(segment), do: segment

  defp agent_route(id), do: "/agents/" <> URI.encode(agent_segment(id), &URI.char_unreserved?/1)

  # Browsers resolve dot segments even when they are percent-encoded.
  defp agent_segment(id) when id in [".", ".."], do: "~" <> id
  defp agent_segment("~" <> _rest = id), do: "~" <> id
  defp agent_segment(id), do: id

  defp assign_scope(_params, uri, socket) do
    query = URI.parse(uri).query || ""

    scope =
      query
      |> Plug.Conn.Query.decode()
      |> Map.take(@scope_keys)
      |> Map.filter(fn {_key, value} -> is_binary(value) and value != "" end)

    {:cont, assign(socket, :studio_scope, scope)}
  end

  defp nonce(conn, keys, kind) when is_map(keys), do: nonce(conn, Map.get(keys, kind), kind)
  defp nonce(_conn, nil, _kind), do: nil

  defp nonce(conn, key, _kind) when is_atom(key) do
    case conn.assigns[key] do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end
end
