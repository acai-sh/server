defmodule AcaiWeb.Api.Plugs.OperationConfigTest do
  @moduledoc """
  Tests for API operation config loading and abuse protection.

  ACIDs:
  - core.OPERATIONS.1 - Runtime-configurable operation limits and rate settings
  - core.OPERATIONS.2 - Abuse rejections are logged through the application logger
  - core.OPERATIONS.3 - Abuse logs include only safe request metadata
  - core.ENG.5 - Shared controller/fallback layer returns JSON errors for 413 responses
  """

  use AcaiWeb.ConnCase, async: false
  import ExUnit.CaptureLog

  alias AcaiWeb.Api.Plugs.OperationConfig

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

  test "loads operation config into conn private assigns", %{conn: conn} do
    conn = %{conn | request_path: "/api/v1/feature-states", method: "POST"}

    conn = OperationConfig.call(conn, [])

    assert conn.private.api_operation_config.request_size_cap
    assert conn.private.api_operation_config.rate_limit
  end

  test "halts oversized requests with a 413 and logs safe metadata", %{conn: conn} do
    Application.put_env(:acai, :api_operations, %{
      default: %{
        request_size_cap: 1,
        semantic_caps: %{},
        rate_limit: %{requests: 1, window_seconds: 60}
      }
    })

    conn =
      %{conn | request_path: "/api/v1/push", method: "POST"}
      |> Plug.Conn.put_private(:phoenix_format, "json")
      |> Plug.Conn.put_req_header("content-length", "10")
      |> Plug.Conn.put_req_header("x-request-id", "req-oversized")

    log =
      capture_log(fn ->
        conn = OperationConfig.call(conn, [])

        assert conn.halted
        assert conn.status == 413
      end)

    assert log =~ "api_rejection"
    assert log =~ "req-oversized"
    assert log =~ "/api/v1/push"
    assert log =~ "request_size_cap"
  end

  test "halts oversized requests based on content-length before controller work", %{conn: conn} do
    Application.put_env(:acai, :api_operations, %{
      default: %{
        request_size_cap: 1,
        semantic_caps: %{},
        rate_limit: %{requests: 1, window_seconds: 60}
      }
    })

    conn =
      %{conn | request_path: "/api/v1/push", method: "POST"}
      |> Plug.Conn.put_private(:phoenix_format, "json")
      |> Plug.Conn.put_req_header("content-length", "4")
      |> Plug.Conn.put_req_header("x-request-id", "req-body-sized")

    conn = OperationConfig.call(conn, [])

    assert conn.halted
    assert conn.status == 413
  end
end
