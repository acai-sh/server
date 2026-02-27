defmodule AcaiWeb.PageController do
  use AcaiWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
