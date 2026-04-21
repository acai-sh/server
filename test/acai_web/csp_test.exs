defmodule AcaiWeb.CspTest do
  use AcaiWeb.ConnCase, async: false

  defp restore_env(key, previous) do
    if is_nil(previous) do
      System.delete_env(key)
    else
      System.put_env(key, previous)
    end
  end

  test "adds the Plausible origin to CSP when configured", %{conn: conn} do
    previous = System.get_env("PLAUSIBLE_SRC")
    System.put_env("PLAUSIBLE_SRC", "https://plausible.io/js/script.js")

    on_exit(fn -> restore_env("PLAUSIBLE_SRC", previous) end)

    conn = get(conn, ~p"/")
    [csp] = get_resp_header(conn, "content-security-policy")

    assert csp =~ "base-uri 'self'"
    assert csp =~ "frame-ancestors 'self'"
    assert csp =~ "script-src 'self' 'unsafe-inline' https://plausible.io"
    assert csp =~ "connect-src 'self' ws: wss: https://plausible.io"
  end

  test "keeps the default CSP when Plausible is not configured", %{conn: conn} do
    previous = System.get_env("PLAUSIBLE_SRC")
    System.delete_env("PLAUSIBLE_SRC")

    on_exit(fn -> restore_env("PLAUSIBLE_SRC", previous) end)

    conn = get(conn, ~p"/")
    [csp] = get_resp_header(conn, "content-security-policy")

    assert csp == "base-uri 'self'; frame-ancestors 'self'"
  end

  test "ignores invalid plausible src values in CSP and HTML", %{conn: conn} do
    previous = System.get_env("PLAUSIBLE_SRC")
    System.put_env("PLAUSIBLE_SRC", "javascript:alert(1)")

    on_exit(fn -> restore_env("PLAUSIBLE_SRC", previous) end)

    conn = get(conn, ~p"/users/log-in")
    [csp] = get_resp_header(conn, "content-security-policy")
    html = html_response(conn, 200)

    assert csp == "base-uri 'self'; frame-ancestors 'self'"
    refute html =~ "javascript:alert(1)"
  end
end
