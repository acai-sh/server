defmodule AcaiWeb.PageControllerTest do
  use AcaiWeb.ConnCase, async: true

  test "GET / redirects to /teams", %{conn: conn} do
    # index-view.REDIRECT.1
    conn = get(conn, ~p"/")
    assert redirected_to(conn) == ~p"/teams"

    # index-view.REDIRECT.1-note
    conn = get(recycle(conn), ~p"/teams")
    assert redirected_to(conn) == ~p"/users/log-in"
  end

  describe "when logged in" do
    setup :register_and_log_in_user

    test "GET / redirects to /teams", %{conn: conn} do
      # index-view.REDIRECT.1
      conn = get(conn, ~p"/")
      assert redirected_to(conn) == ~p"/teams"

      # index-view.REDIRECT.1-note
      conn = get(recycle(conn), ~p"/teams")
      assert html_response(conn, 200) =~ "Teams"
    end
  end
end
