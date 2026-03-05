defmodule AcaiWeb.PageController do
  use AcaiWeb, :controller

  def home(conn, _params) do
    # index-view.REDIRECT.1
    redirect(conn, to: ~p"/teams")
  end
end
