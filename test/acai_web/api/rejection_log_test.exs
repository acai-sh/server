defmodule AcaiWeb.Api.RejectionLogTest do
  @moduledoc """
  Tests for structured API rejection logging.

  ACIDs:
  - core.OPERATIONS.2 - Security and abuse rejections are emitted through the application logger
  - core.OPERATIONS.3 - Logs include safe metadata without raw secrets or payloads
  """

  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

  alias AcaiWeb.Api.RejectionLog

  test "security log includes safe request metadata" do
    conn =
      %Plug.Conn{request_path: "/api/v1/push", method: "POST"}
      |> Plug.Conn.put_req_header("x-request-id", "req-123")

    log =
      capture_log(fn ->
        :ok = RejectionLog.security(conn, "Authorization header required")
      end)

    assert log =~ "api_rejection"
    assert log =~ "req-123"
    assert log =~ "/api/v1/push"
  end

  test "api_rejection events are filtered at the logger boundary" do
    assert RejectionLog.filter_api_rejection(%{meta: %{api_rejection: true}}, nil) == :stop
    assert RejectionLog.filter_api_rejection(%{meta: %{}}, nil) == :ignore
  end

  test "token fingerprints are non-secret and stable" do
    fingerprint = RejectionLog.token_fingerprint("Bearer secret-token-value")

    assert fingerprint == RejectionLog.token_fingerprint("Bearer secret-token-value")
    refute fingerprint =~ "secret-token-value"
  end
end
