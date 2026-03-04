defmodule AcaiWeb.TeamTokensLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.AccountsFixtures
  import Acai.DataModelFixtures

  alias Acai.Repo
  alias Acai.Teams.AccessToken

  defp setup_team_with_owner(user) do
    team = team_fixture()
    user_team_role_fixture(team, user, %{title: "owner"})
    team
  end

  describe "unauthenticated access" do
    test "redirects to log-in", %{conn: conn} do
      team = team_fixture()
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/t/#{team.id}/tokens")
      assert path == ~p"/users/log-in"
    end
  end

  describe "mount" do
    setup :register_and_log_in_user

    # team-tokens.TATSEC.5
    test "authenticated team member can view the tokens page", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "readonly"})
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      assert has_element?(view, "#tokens-list")
    end

    # team-tokens.MAIN.2
    test "renders the token education section", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      assert has_element?(view, "#token-education")
      assert has_element?(view, "#token-education", "tats:admin")
      assert has_element?(view, "#token-education", "team:admin")
    end

    # team-tokens.MAIN.1
    test "lists all tokens for the team including those created by other users", %{
      conn: conn,
      user: user
    } do
      team = setup_team_with_owner(user)
      other_user = user_fixture()
      user_team_role_fixture(team, other_user, %{title: "developer"})

      token1 = access_token_fixture(team, user, %{name: "My Token"})
      token2 = access_token_fixture(team, other_user, %{name: "Their Token"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      assert has_element?(view, "#tokens-list", token1.name)
      assert has_element?(view, "#tokens-list", token2.name)
    end

    # team-tokens.MAIN.1-1
    test "shows token prefix, name, and created-by email", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      token = access_token_fixture(team, user, %{name: "CLI Token", token_prefix: "at_abc1"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      assert has_element?(view, "#tokens-list", token.name)
      assert has_element?(view, "#tokens-list", token.token_prefix)
      assert has_element?(view, "#tokens-list", user.email)
    end

    # team-tokens.USAGE.1
    test "renders the usage coming soon section", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      assert has_element?(view, "#usage-section")
      assert has_element?(view, "#usage-section", "Coming soon")
    end
  end

  describe "create token button permissions" do
    setup :register_and_log_in_user

    # team-tokens.TATSEC.4
    test "create token button is disabled for developer role", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "developer"})
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      assert has_element?(view, "#create-token-btn[disabled]")
    end

    # team-tokens.TATSEC.4
    test "create token button is disabled for readonly role", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "readonly"})
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      assert has_element?(view, "#create-token-btn[disabled]")
    end

    # team-tokens.TATSEC.4
    test "create token button is enabled for owner", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      refute has_element?(view, "#create-token-btn[disabled]")
    end
  end

  describe "create token modal" do
    setup :register_and_log_in_user

    # team-tokens.MAIN.3
    test "owner can open the create token modal", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")

      refute has_element?(view, "#create-token-modal")
      view |> element("#create-token-btn") |> render_click()
      assert has_element?(view, "#create-token-modal")
    end

    test "closing the modal hides it", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#create-token-btn") |> render_click()

      assert has_element?(view, "#create-token-modal")
      view |> element("#close-create-modal-btn") |> render_click()
      refute has_element?(view, "#create-token-modal")
    end

    # team-tokens.MAIN.3
    test "modal shows name input and expiry date picker", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#create-token-btn") |> render_click()

      assert has_element?(view, "#create-token-form input[type='text']")
      assert has_element?(view, "#create-token-form input[type='datetime-local']")
    end

    # team-tokens.MAIN.3-1
    test "modal does not show a scopes selector", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#create-token-btn") |> render_click()

      refute has_element?(view, "#create-token-form select")
      refute has_element?(view, "#create-token-form", "scopes")
    end

    test "submitting with empty name shows validation error", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#create-token-btn") |> render_click()

      view
      |> form("#create-token-form", %{"token" => %{"name" => ""}})
      |> render_submit()

      assert has_element?(view, "#create-token-form", "can't be blank")
    end

    # team-tokens.MAIN.4
    test "submitting a valid token shows the raw token reveal area", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#create-token-btn") |> render_click()

      view
      |> form("#create-token-form", %{"token" => %{"name" => "My CLI Token"}})
      |> render_submit()

      assert has_element?(view, "#token-reveal")
      assert has_element?(view, "#raw-token-display")
      assert has_element?(view, "#token-reveal", "won't be able to see it again")
    end

    # team-tokens.MAIN.4-1
    test "token reveal area has a copy button", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#create-token-btn") |> render_click()

      view
      |> form("#create-token-form", %{"token" => %{"name" => "Copy Test"}})
      |> render_submit()

      assert has_element?(view, "#copy-token-btn")
    end

    # team-tokens.MAIN.4
    test "created token appears in the token list", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#create-token-btn") |> render_click()

      view
      |> form("#create-token-form", %{"token" => %{"name" => "Stream Token"}})
      |> render_submit()

      assert has_element?(view, "#tokens-list", "Stream Token")
    end

    # team-tokens.MAIN.4
    test "dismissing the token reveal closes the modal", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#create-token-btn") |> render_click()

      view
      |> form("#create-token-form", %{"token" => %{"name" => "Dismiss Test"}})
      |> render_submit()

      assert has_element?(view, "#token-reveal")
      view |> element("#dismiss-token-btn") |> render_click()

      refute has_element?(view, "#create-token-modal")
    end
  end

  describe "revoke token" do
    setup :register_and_log_in_user

    # team-tokens.TATSEC.4
    test "revoke button is disabled for developer role", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "developer"})
      owner = user_fixture()
      user_team_role_fixture(team, owner, %{title: "owner"})
      token = access_token_fixture(team, owner, %{name: "Test"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      assert has_element?(view, "#revoke-btn-#{token.id}[disabled]")
    end

    # team-tokens.TATSEC.4
    test "revoke button is disabled for readonly role", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "readonly"})
      owner = user_fixture()
      user_team_role_fixture(team, owner, %{title: "owner"})
      token = access_token_fixture(team, owner, %{name: "Test"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      assert has_element?(view, "#revoke-btn-#{token.id}[disabled]")
    end

    # team-tokens.MAIN.5-1
    test "owner clicking revoke opens the confirmation modal", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      token = access_token_fixture(team, user, %{name: "Revoke Me"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")

      refute has_element?(view, "#revoke-token-modal")
      view |> element("#revoke-btn-#{token.id}") |> render_click()
      assert has_element?(view, "#revoke-token-modal")
    end

    test "cancel closes the revoke modal", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      token = access_token_fixture(team, user, %{name: "Cancel Revoke"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#revoke-btn-#{token.id}") |> render_click()

      assert has_element?(view, "#revoke-token-modal")
      view |> element("#cancel-revoke-btn") |> render_click()
      refute has_element?(view, "#revoke-token-modal")
    end

    # team-tokens.MAIN.5
    test "confirming revocation marks the token as revoked in the stream", %{
      conn: conn,
      user: user
    } do
      team = setup_team_with_owner(user)
      token = access_token_fixture(team, user, %{name: "To Revoke"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#revoke-btn-#{token.id}") |> render_click()
      view |> element("#confirm-revoke-btn") |> render_click()

      refute has_element?(view, "#revoke-token-modal")

      persisted = Repo.get!(AccessToken, token.id)
      assert not is_nil(persisted.revoked_at)
    end

    # team-tokens.MAIN.5
    test "revoked token shows revoked badge in the list", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      token = access_token_fixture(team, user, %{name: "Badge Token"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      view |> element("#revoke-btn-#{token.id}") |> render_click()
      view |> element("#confirm-revoke-btn") |> render_click()

      assert has_element?(view, "#tokens-list", "Revoked")
    end

    test "revoke button is disabled for already-revoked tokens", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      now = DateTime.utc_now(:second)

      token =
        access_token_fixture(team, user, %{
          name: "Already Revoked",
          revoked_at: now
        })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.id}/tokens")
      assert has_element?(view, "#revoke-btn-#{token.id}[disabled]")
    end
  end
end
