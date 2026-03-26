defmodule Acai.Teams.TokenAuthTest do
  @moduledoc """
  Tests for token authentication functionality in the Teams context.

  ACIDs:
  - push.AUTH.1 - Push requires a valid, non-expired, non-revoked API token
  """

  use Acai.DataCase, async: true

  import Acai.DataModelFixtures
  alias Acai.AccountsFixtures
  alias Acai.Repo
  alias Acai.Teams
  alias Acai.Teams.AccessToken

  describe "authenticate_api_token/1" do
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

    test "returns token and team for valid token", %{token: token, team: team} do
      assert {:ok, %{token: auth_token, team: auth_team}} =
               Teams.authenticate_api_token(token.raw_token)

      assert auth_token.id == token.id
      assert auth_team.id == team.id

      # Verify last_used_at was updated
      refute is_nil(auth_token.last_used_at)
    end

    test "returns error for unknown token" do
      assert {:error, "Invalid token"} =
               Teams.authenticate_api_token("at_unknowntoken123456789")
    end

    test "returns error for revoked token", %{token: token} do
      # Revoke the token
      {:ok, _} = Teams.revoke_token(token)

      assert {:error, "Token has been revoked"} =
               Teams.authenticate_api_token(token.raw_token)
    end

    test "returns error for expired token", %{user: user, team: team} do
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

      assert {:error, "Token has expired"} =
               Teams.authenticate_api_token(raw_token)
    end

    test "updates last_used_at on successful authentication", %{token: token} do
      # Verify token initially has no last_used_at
      token_record = Teams.get_access_token!(token.id)
      assert is_nil(token_record.last_used_at)

      # Authenticate
      assert {:ok, %{token: auth_token}} = Teams.authenticate_api_token(token.raw_token)

      # Verify last_used_at is now set
      refute is_nil(auth_token.last_used_at)

      # Verify it's a recent timestamp
      now = DateTime.utc_now()
      diff = DateTime.diff(now, auth_token.last_used_at, :second)
      # Within 5 seconds
      assert diff < 5
    end
  end

  describe "token_has_scope?/2" do
    setup do
      user = AccountsFixtures.user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      # Generate a token with specific scopes
      {:ok, token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Scoped Token", scopes: ["specs:read", "specs:write"]}
        )

      %{token: token}
    end

    test "returns true when token has the required scope", %{token: token} do
      assert Teams.token_has_scope?(token, "specs:read")
      assert Teams.token_has_scope?(token, "specs:write")
    end

    test "returns false when token does not have the required scope", %{token: token} do
      refute Teams.token_has_scope?(token, "refs:read")
      refute Teams.token_has_scope?(token, "states:write")
      refute Teams.token_has_scope?(token, "nonexistent:scope")
    end
  end
end
