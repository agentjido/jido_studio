defmodule StudioPlaygroundWeb.PageController do
  use StudioPlaygroundWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
