defmodule AcaiWeb.Api.Plugs.ParsersTest do
  @moduledoc """
  Tests for API request parsing with runtime body-size limits.

  ACIDs:
  - core.OPERATIONS.1 - Request-size limits are enforced while reading API bodies
  - core.OPERATIONS.2 - Oversized rejections are logged through the application logger
  - core.OPERATIONS.3 - Abuse logs include safe request metadata without payloads
  """

  use AcaiWeb.ConnCase, async: false

  import ExUnit.CaptureLog
  import Plug.Conn

  setup do
    original = Application.get_env(:acai, :api_operations)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:acai, :api_operations)
      else
        Application.put_env(:acai, :api_operations, original)
      end
    end)

    :ok
  end

  test "halts oversized API request bodies during parsing" do
    Application.put_env(:acai, :api_operations, %{
      default: %{
        request_size_cap: 1,
        semantic_caps: %{},
        rate_limit: %{requests: 1, window_seconds: 60}
      },
      push: %{
        request_size_cap: 1,
        semantic_caps: %{},
        rate_limit: %{requests: 1, window_seconds: 60}
      }
    })

    conn =
      Plug.Test.conn("POST", "/api/v1/push", Jason.encode!(%{foo: "bar"}))
      |> put_req_header("content-type", "application/json")
      |> put_req_header("accept", "application/json")
      |> put_req_header("x-request-id", "req-body-limit")

    log =
      capture_log(fn ->
        conn = AcaiWeb.Endpoint.call(conn, [])

        assert conn.status == 413
        assert conn.halted
        refute Map.has_key?(conn.assigns, :raw_body)
      end)

    assert log =~ "api_rejection"
    assert log =~ "req-body-limit"
    assert log =~ "/api/v1/push"
  end

  test "browser routes bypass api rejection logging for oversized bodies" do
    Application.put_env(:acai, :api_operations, %{
      default: %{
        request_size_cap: 1,
        semantic_caps: %{},
        rate_limit: %{requests: 1, window_seconds: 60}
      },
      push: %{
        request_size_cap: 1,
        semantic_caps: %{},
        rate_limit: %{requests: 1, window_seconds: 60}
      }
    })

    params = %{"user" => %{"email" => String.duplicate("a", 100_000)}}

    conn =
      build_conn()
      |> put_req_header("accept", "text/html")
      |> put_req_header("x-request-id", "req-browser-body-limit")

    log =
      capture_log(fn ->
        conn = post(conn, ~p"/users/log-in", params)

        refute conn.status == 413

        refute get_resp_header(conn, "content-type")
               |> Enum.any?(&String.contains?(&1, "application/json"))
      end)

    refute log =~ "api_rejection"
    refute log =~ "req-browser-body-limit"
  end
end
