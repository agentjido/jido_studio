defmodule JidoStudio.Extension do
  @moduledoc """
  Behaviour for optional Studio feature extensions.

  Extensions contribute extra routes and sidebar navigation when their backing
  package is available in the host project.
  """

  @type route :: %{
          required(:path) => String.t(),
          required(:live_view) => module(),
          required(:action) => atom()
        }

  @type nav_item :: %{
          required(:path) => String.t(),
          required(:label) => String.t(),
          required(:icon) => String.t()
        }

  @type nav_section :: %{
          required(:id) => atom() | String.t(),
          required(:label) => String.t(),
          required(:items) => [nav_item()]
        }

  @callback id() :: atom()
  @callback installed?() :: boolean()
  @callback routes() :: [route()]
  @callback nav_sections() :: [nav_section()]
end
