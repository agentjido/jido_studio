defmodule JidoStudio.Resolver do
  @moduledoc """
  Behaviour for customizing Jido Studio access and display.

  Implement this behaviour to control who can access the studio,
  what actions they can perform, and how data is displayed.

  ## Example

      defmodule MyApp.StudioResolver do
        @behaviour JidoStudio.Resolver

        @impl true
        def resolve_user(conn) do
          conn.assigns[:current_user]
        end

        @impl true
        def resolve_access(user) do
          case user do
            %{role: :admin} -> :all
            %{role: :developer} -> :read_only
            _ -> {:forbidden, "/login"}
          end
        end
      end
  """

  @type user :: term()
  @type access :: :all | :read_only | {:forbidden, redirect_path :: String.t()}

  @callback resolve_user(conn :: Plug.Conn.t()) :: user()

  @callback resolve_access(user()) :: access()
end

defmodule JidoStudio.Resolver.Default do
  @moduledoc false
  @behaviour JidoStudio.Resolver

  @impl true
  def resolve_user(_conn), do: nil

  @impl true
  def resolve_access(_user), do: :all
end
