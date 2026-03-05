defmodule AcaiWeb.TeamTokensLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.AccountsFixtures
  import Acai.DataModelFixtures
  import Ecto.Query

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
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/t/#{team.name}/tokens")
      assert path == ~p"/users/log-in"
    end
  end

  describe "mount" do
    setup :register_and_log_in_user

    # team-tokens.TATSEC.5
    test "authenticated team member can view the tokens page", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "readonly"})
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      assert has_element?(view, "#tokens-list")
    end

    # team-tokens.MAIN.2
    test "renders the token education section", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      assert has_element?(view, "#token-education")
      assert has_element?(view, "#token-education", "manage users")
      assert has_element?(view, "#token-education", "other access tokens")
    end

    # team-tokens.MAIN.1
    test "lists only active and non-expired tokens for the team", %{
      conn: conn,
      user: user
    } do
      team = setup_team_with_owner(user)
      other_user = user_fixture()
      user_team_role_fixture(team, other_user, %{title: "developer"})

      token1 = access_token_fixture(team, user, %{name: "Active Token"})

      _token2 =
        access_token_fixture(team, other_user, %{
          name: "Revoked Token",
          revoked_at: DateTime.utc_now()
        })

      token3 = access_token_fixture(team, other_user, %{name: "Expired Token"})
      past = DateTime.utc_now() |> DateTime.add(-3600, :second)

      Repo.update_all(
        from(t in AccessToken, where: t.id == ^token3.id),
        set: [expires_at: past]
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      assert has_element?(view, "#tokens-list", token1.name)
      refute has_element?(view, "#tokens-list", "Revoked Token")
      refute has_element?(view, "#tokens-list", "Expired Token")
    end

    # team-tokens.MAIN.1-1
    test "shows token prefix, name, and created-by email", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      token = access_token_fixture(team, user, %{name: "CLI Token", token_prefix: "at_abc1"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      assert has_element?(view, "#tokens-list", token.name)
      assert has_element?(view, "#tokens-list", token.token_prefix)
      assert has_element?(view, "#tokens-list", user.email)
    end

    # team-tokens.USAGE.1
    test "renders the usage coming soon section", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
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
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      assert has_element?(view, "#create-token-btn[disabled]")
    end

    # team-tokens.TATSEC.4
    test "create token button is disabled for readonly role", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "readonly"})
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      assert has_element?(view, "#create-token-btn[disabled]")
    end

    # team-tokens.TATSEC.4
    test "create token button is enabled for owner", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      refute has_element?(view, "#create-token-btn[disabled]")
    end
  end

  describe "create token modal" do
    setup :register_and_log_in_user

    # team-tokens.MAIN.3
    test "owner can open the create token modal", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")

      refute has_element?(view, "#create-token-modal")
      view |> element("#create-token-btn") |> render_click()
      assert has_element?(view, "#create-token-modal")
    end

    test "closing the modal hides it", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      view |> element("#create-token-btn") |> render_click()

      assert has_element?(view, "#create-token-modal")
      view |> element("#close-create-modal-btn") |> render_click()
      refute has_element?(view, "#create-token-modal")
    end

    # team-tokens.MAIN.3
    test "modal shows name input and expiry date picker", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      view |> element("#create-token-btn") |> render_click()

      assert has_element?(view, "#create-token-form input[type='text']")
      assert has_element?(view, "#create-token-form input[type='datetime-local']")
    end

    # team-tokens.MAIN.3-1
    test "modal does not show a scopes selector", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      view |> element("#create-token-btn") |> render_click()

      refute has_element?(view, "#create-token-form select")
      refute has_element?(view, "#create-token-form", "scopes")
    end

    test "submitting with empty name shows validation error", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      view |> element("#create-token-btn") |> render_click()

      view
      |> form("#create-token-form", %{"token" => %{"name" => ""}})
      |> render_submit()

      assert has_element?(view, "#create-token-form", "can't be blank")
    end

    # team-tokens.MAIN.4
    test "submitting a valid token shows the raw token reveal area", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
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
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      view |> element("#create-token-btn") |> render_click()

      view
      |> form("#create-token-form", %{"token" => %{"name" => "Copy Test"}})
      |> render_submit()

      assert has_element?(view, "#copy-token-btn")
    end

    # team-tokens.MAIN.4
    test "created token appears in the token list", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      view |> element("#create-token-btn") |> render_click()

      view
      |> form("#create-token-form", %{"token" => %{"name" => "Stream Token"}})
      |> render_submit()

      assert has_element?(view, "#tokens-list", "Stream Token")
    end

    # team-tokens.MAIN.4
    test "dismissing the token reveal closes the modal", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
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

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      assert has_element?(view, "#revoke-btn-#{token.id}[disabled]")
    end

    # team-tokens.TATSEC.4
    test "revoke button is disabled for readonly role", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "readonly"})
      owner = user_fixture()
      user_team_role_fixture(team, owner, %{title: "owner"})
      token = access_token_fixture(team, owner, %{name: "Test"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      assert has_element?(view, "#revoke-btn-#{token.id}[disabled]")
    end

    # team-tokens.MAIN.5-1
    test "owner clicking revoke opens the confirmation modal", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      token = access_token_fixture(team, user, %{name: "Revoke Me"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")

      refute has_element?(view, "#revoke-token-modal")
      view |> element("#revoke-btn-#{token.id}") |> render_click()
      assert has_element?(view, "#revoke-token-modal")
    end

    test "cancel closes the revoke modal", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      token = access_token_fixture(team, user, %{name: "Cancel Revoke"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      view |> element("#revoke-btn-#{token.id}") |> render_click()

      assert has_element?(view, "#revoke-token-modal")
      view |> element("#cancel-revoke-btn") |> render_click()
      refute has_element?(view, "#revoke-token-modal")
    end

    # team-tokens.MAIN.5 / INACTIVE.1
    test "confirming revocation transfers the token to the inactive stream", %{
      conn: conn,
      user: user
    } do
      team = setup_team_with_owner(user)
      token = access_token_fixture(team, user, %{name: "To Revoke"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      assert has_element?(view, "#tokens-list", token.name)

      view |> element("#revoke-btn-#{token.id}") |> render_click()
      view |> element("#confirm-revoke-btn") |> render_click()

      refute has_element?(view, "#revoke-token-modal")
      refute has_element?(view, "#tokens-list", token.name)

      # Should be in inactive list (expand it first)
      view |> element("#toggle-inactive-btn") |> render_click()
      assert has_element?(view, "#inactive-tokens-list", token.name)
    end
  end

  describe "inactive tokens section (INACTIVE)" do
    setup :register_and_log_in_user

    # team-tokens.INACTIVE.1
    test "revoked tokens appear in the separate inactive tokens list", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)

      token =
        access_token_fixture(team, user, %{name: "Old Token", revoked_at: DateTime.utc_now()})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")

      # Toggle expanded to see them
      view |> element("#toggle-inactive-btn") |> render_click()

      refute has_element?(view, "#tokens-list", token.name)
      assert has_element?(view, "#inactive-tokens-list", token.name)
    end

    # team-tokens.INACTIVE.1
    test "expired tokens appear in the separate inactive tokens list", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)

      token = access_token_fixture(team, user, %{name: "Expired Token"})
      past = DateTime.utc_now() |> DateTime.add(-3600, :second)

      Repo.update_all(
        from(t in AccessToken, where: t.id == ^token.id),
        set: [expires_at: past]
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")

      # Toggle expanded to see them
      view |> element("#toggle-inactive-btn") |> render_click()

      refute has_element?(view, "#tokens-list", token.name)
      assert has_element?(view, "#inactive-tokens-list", token.name)
      assert has_element?(view, "#inactive-tokens-list", "Expired")
    end

    # team-tokens.INACTIVE.2
    test "revoked tokens show a 'Revoked' badge and the revocation date", %{
      conn: conn,
      user: user
    } do
      team = setup_team_with_owner(user)
      now = DateTime.utc_now(:second)
      _token = access_token_fixture(team, user, %{name: "Date Test", revoked_at: now})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")
      view |> element("#toggle-inactive-btn") |> render_click()

      assert has_element?(view, "#inactive-tokens-list", "Revoked")
      assert has_element?(view, "#inactive-tokens-list", Calendar.strftime(now, "%b %d, %Y"))
    end

    # team-tokens.INACTIVE.3
    test "inactive section is collapsed by default and can be toggled", %{conn: conn, user: user} do
      team = setup_team_with_owner(user)
      access_token_fixture(team, user, %{name: "Collapsible", revoked_at: DateTime.utc_now()})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/tokens")

      assert has_element?(view, "#inactive-tokens-container.hidden")

      view |> element("#toggle-inactive-btn") |> render_click()
      refute has_element?(view, "#inactive-tokens-container.hidden")

      view |> element("#toggle-inactive-btn") |> render_click()
      assert has_element?(view, "#inactive-tokens-container.hidden")
    end
  end
end
