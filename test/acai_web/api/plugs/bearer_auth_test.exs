defmodule AcaiWeb.Api.Plugs.BearerAuthTest do
  @moduledoc """
  Tests for the BearerAuth plug.

  ACIDs:
  - push.AUTH.1 - Push requires a valid, non-expired, non-revoked API token
  - core.ENG.8 - All routes require Authorization header with Bearer token
  - core.OPERATIONS.2 - Security rejections are logged through the application logger
  - core.OPERATIONS.3 - Security logs include safe metadata without secret credentials
  """

  use AcaiWeb.ConnCase, async: true

  import ExUnit.CaptureLog

  import Acai.DataModelFixtures
  alias Acai.AccountsFixtures
  alias Acai.Repo

  alias Acai.Teams
  alias Acai.Teams.AccessToken
  alias AcaiWeb.Api.RejectionLog

  describe "bearer token authentication" do
    setup do
      user = AccountsFixtures.user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      # Generate a token with known raw value
      {:ok, token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Test Token"}
        )

      %{team: team, user: user, token: token}
    end

    test "valid token authenticates and assigns token and team", %{
      conn: conn,
      token: token,
      team: team
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> AcaiWeb.Api.Plugs.BearerAuth.call([])

      # Should not be halted
      refute conn.halted

      # Should have token and team assigned
      assert conn.assigns.current_token.id == token.id
      assert conn.assigns.current_team.id == team.id
      assert conn.assigns.current_team_id == team.id

      # last_used_at should be updated
      updated_token = Teams.get_access_token!(token.id)
      refute is_nil(updated_token.last_used_at)
    end

    test "missing Authorization header returns 401", %{conn: conn} do
      conn = AcaiWeb.Api.Plugs.BearerAuth.call(conn, [])

      assert conn.halted
      assert conn.status == 401

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Authorization header required"
    end

    test "malformed Authorization header (no Bearer prefix) returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic sometoken")
        |> AcaiWeb.Api.Plugs.BearerAuth.call([])

      assert conn.halted
      assert conn.status == 401

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Authorization header must use Bearer scheme"
    end

    test "empty Bearer token returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer ")
        |> AcaiWeb.Api.Plugs.BearerAuth.call([])

      assert conn.halted
      assert conn.status == 401

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Invalid token"
    end

    test "unknown token returns 401", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer at_invalidtoken123")
        |> AcaiWeb.Api.Plugs.BearerAuth.call([])

      assert conn.halted
      assert conn.status == 401

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Invalid token"
    end

    test "revoked token returns 401", %{conn: conn, token: token} do
      # Revoke the token
      {:ok, _} = Teams.revoke_token(token)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> AcaiWeb.Api.Plugs.BearerAuth.call([])

      assert conn.halted
      assert conn.status == 401

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Token has been revoked"
    end

    test "expired token returns 401", %{conn: conn, user: user, team: team} do
      # Create an expired token by inserting directly (bypassing changeset validation)
      raw_token = "at_" <> Base.url_encode64(:crypto.strong_rand_bytes(32), padding: false)
      token_hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)
      token_prefix = String.slice(raw_token, 0, 10)
      past_date = DateTime.utc_now() |> DateTime.add(-1, :day)

      # Insert directly to bypass validation
      %AccessToken{
        id: Acai.UUIDv7.autogenerate(),
        name: "Expired Token",
        token_hash: token_hash,
        token_prefix: token_prefix,
        scopes: ["specs:read"],
        expires_at: DateTime.truncate(past_date, :second),
        team_id: team.id,
        user_id: user.id,
        inserted_at: DateTime.utc_now(:second),
        updated_at: DateTime.utc_now(:second)
      }
      |> Repo.insert!()

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{raw_token}")
        |> AcaiWeb.Api.Plugs.BearerAuth.call([])

      assert conn.halted
      assert conn.status == 401

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Token has expired"
    end

    test "missing Authorization header emits a structured security log", %{conn: conn} do
      conn = %{conn | request_path: "/api/v1/push", method: "POST"}
      conn = Plug.Conn.put_req_header(conn, "x-request-id", "req-log-1")

      log =
        capture_log(fn ->
          conn = AcaiWeb.Api.Plugs.BearerAuth.call(conn, [])
          assert conn.status == 401
        end)

      assert log =~ "api_rejection"
      assert log =~ "req-log-1"
      assert log =~ "/api/v1/push"
      assert log =~ "Authorization header required"
    end

    test "invalid token logs a non-secret token fingerprint", %{conn: conn} do
      raw_token = "at_invalidtoken123"
      fingerprint = RejectionLog.token_fingerprint(raw_token)

      conn = %{conn | request_path: "/api/v1/push", method: "POST"}
      conn = Plug.Conn.put_req_header(conn, "authorization", "Bearer #{raw_token}")

      log =
        capture_log(fn ->
          conn = AcaiWeb.Api.Plugs.BearerAuth.call(conn, [])
          assert conn.status == 401
        end)

      assert log =~ "api_rejection"
      assert log =~ fingerprint
      refute log =~ raw_token
    end
  end
end
