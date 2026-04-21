defmodule AcaiWeb.TeamLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.AccountsFixtures
  import Acai.DataModelFixtures

  alias Acai.Repo

  # Helper to set up a team with an owner (the logged-in user)
  defp create_team_with_owner(user) do
    team = team_fixture()
    role = user_team_role_fixture(team, user, %{title: "owner"})
    {team, role}
  end

  describe "unauthenticated access" do
    test "redirects to log-in", %{conn: conn} do
      team = team_fixture()
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/t/#{team.name}")
      assert path == ~p"/users/log-in"
    end
  end

  describe "mount" do
    setup :register_and_log_in_user

    # team-view.MAIN.1
    test "renders the team name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "h1", team.name)
    end

    # team-view.MAIN.2
    test "renders the access tokens card linking to /tokens", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#access-tokens-card")
      assert has_element?(view, "a[href='/t/#{team.name}/tokens']")
    end

    # team-view.MAIN.3
    test "renders the team settings button linking to /settings", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#team-settings-btn")
      assert has_element?(view, "a[href='/t/#{team.name}/settings']")
    end

    # team-view.MEMBERS.1
    test "renders the members list with user email and role", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#members-list")
      assert has_element?(view, "#member-#{user.id}", user.email)
      assert has_element?(view, "#member-#{user.id}", "owner")
    end
  end

  describe "admin dashboard entry point" do
    setup :register_and_log_in_user

    test "dashboard.MAIN.1 shows the admin section on a whitelisted team page for whitelisted users",
         %{
           conn: conn,
           user: user
         } do
      team = team_fixture(%{global_admin: true})
      user_team_role_fixture(team, user, %{title: "developer"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "#admin-section")
      assert has_element?(view, "#admin-dashboard-btn")
    end

    test "dashboard.MAIN.1-1 links the dashboard button to /admin/dashboard/home", %{
      conn: conn,
      user: user
    } do
      team = team_fixture(%{global_admin: true})
      user_team_role_fixture(team, user, %{title: "readonly"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "a#admin-dashboard-btn[href='/admin/dashboard/home']")
    end

    test "dashboard.MAIN.2 hides the admin section for users with no global admin memberships", %{
      conn: conn,
      user: user
    } do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      refute has_element?(view, "#admin-section")
      refute has_element?(view, "#admin-dashboard-btn")
    end

    test "dashboard.MAIN.2-1 hides the admin section on a non-whitelisted team page even when another team grants global admin access",
         %{conn: conn, user: user} do
      current_team = team_fixture()
      user_team_role_fixture(current_team, user, %{title: "readonly"})

      global_admin_team = team_fixture(%{global_admin: true})
      user_team_role_fixture(global_admin_team, user, %{title: "readonly"})

      {:ok, view, _html} = live(conn, ~p"/t/#{current_team.name}")

      refute has_element?(view, "#admin-section")
      refute has_element?(view, "#admin-dashboard-btn")
    end
  end

  describe "invite button visibility" do
    setup :register_and_log_in_user

    # team-view.MEMBERS.2
    test "invite button is present for admin (owner) users", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#invite-member-btn")
    end

    # team-view.MEMBERS.2-1
    test "invite button is disabled for readonly user", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "readonly"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#invite-member-btn[disabled]")
    end

    # team-view.MEMBERS.2-1
    test "invite button is disabled for developer user", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "developer"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#invite-member-btn[disabled]")
    end

    # team-view.MEMBERS.2-1
    test "invite button is enabled for owner", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      refute has_element?(view, "#invite-member-btn[disabled]")
    end
  end

  describe "edit button visibility" do
    setup :register_and_log_in_user

    # team-view.MEMBERS.3-1
    test "edit buttons are disabled for readonly user", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "readonly"})
      other = user_fixture()
      user_team_role_fixture(team, other, %{title: "developer"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#edit-btn-#{other.id}[disabled]")
    end

    # team-view.MEMBERS.3-1
    test "edit buttons are disabled for developer user", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "developer"})
      other = user_fixture()
      user_team_role_fixture(team, other, %{title: "readonly"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#edit-btn-#{other.id}[disabled]")
    end

    # team-view.MEMBERS.3-2
    test "owner cannot edit their own role when they are the last owner", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#edit-btn-#{user.id}[disabled]")
    end

    # team-view.MEMBERS.3-2
    test "owner can edit their own role when another owner exists", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      other_owner = user_fixture()
      user_team_role_fixture(team, other_owner, %{title: "owner"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      refute has_element?(view, "#edit-btn-#{user.id}[disabled]")
    end

    # team-view.MEMBERS.3
    test "owner can see edit buttons for other members", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      other = user_fixture()
      user_team_role_fixture(team, other, %{title: "developer"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#edit-btn-#{other.id}")
      refute has_element?(view, "#edit-btn-#{other.id}[disabled]")
    end
  end

  describe "invite modal" do
    setup :register_and_log_in_user

    # team-view.MEMBERS.2
    test "clicking invite button opens the invite modal", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      refute has_element?(view, "#invite-modal")
      view |> element("#invite-member-btn") |> render_click()
      assert has_element?(view, "#invite-modal")
    end

    test "closing the invite modal hides it", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      view |> element("#invite-member-btn") |> render_click()
      assert has_element?(view, "#invite-modal")

      view |> element("#close-invite-modal-btn") |> render_click()
      refute has_element?(view, "#invite-modal")
    end

    # team-view.INVITE.1
    test "invite modal renders email input", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#invite-member-btn") |> render_click()

      assert has_element?(view, "#invite-form input[type='email']")
    end

    # team-view.INVITE.2
    test "invite modal renders role dropdown", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#invite-member-btn") |> render_click()

      assert has_element?(view, "#invite-form select")
    end

    # team-view.INVITE.3
    test "invite modal renders Send Invitation button", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#invite-member-btn") |> render_click()

      assert has_element?(view, "#send-invitation-btn")
    end

    # team-view.INVITE.3-1
    test "shows error when invitee is already a team member", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      other = user_fixture()
      user_team_role_fixture(team, other, %{title: "developer"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#invite-member-btn") |> render_click()

      view
      |> form("#invite-form", %{"invite" => %{"email" => other.email, "role" => "developer"}})
      |> render_submit()

      assert has_element?(view, "#invite-error-msg")
    end

    # team-view.INVITE.3-2
    test "creates a new user when email doesn't exist and adds them to team", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      new_email = Acai.AccountsFixtures.unique_user_email()

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#invite-member-btn") |> render_click()

      view
      |> form("#invite-form", %{"invite" => %{"email" => new_email, "role" => "developer"}})
      |> render_submit()

      refute has_element?(view, "#invite-modal")
      assert has_element?(view, "#members-list", new_email)
    end

    # team-view.INVITE.3-4
    test "immediately adds an existing user to the team without acceptance state", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      existing = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#invite-member-btn") |> render_click()

      view
      |> form("#invite-form", %{"invite" => %{"email" => existing.email, "role" => "developer"}})
      |> render_submit()

      refute has_element?(view, "#invite-modal")
      assert has_element?(view, "#member-#{existing.id}")
    end
  end

  describe "edit role modal" do
    setup :register_and_log_in_user

    setup %{user: user} do
      {team, _role} = create_team_with_owner(user)
      other = user_fixture()
      user_team_role_fixture(team, other, %{title: "developer"})
      %{team: team, other: other}
    end

    # team-view.MEMBERS.3
    test "edit modal opens when edit button is clicked", %{conn: conn, team: team, other: other} do
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      refute has_element?(view, "#edit-role-modal")
      view |> element("#edit-btn-#{other.id}") |> render_click()
      assert has_element?(view, "#edit-role-modal")
    end

    test "closing the edit modal hides it", %{conn: conn, team: team, other: other} do
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#edit-btn-#{other.id}") |> render_click()

      assert has_element?(view, "#edit-role-modal")
      view |> element("#close-edit-modal-btn") |> render_click()
      refute has_element?(view, "#edit-role-modal")
    end

    # team-view.EDIT_ROLE.1
    test "edit modal renders Save and Cancel buttons", %{conn: conn, team: team, other: other} do
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#edit-btn-#{other.id}") |> render_click()

      assert has_element?(view, "#save-role-btn")
      assert has_element?(view, "#cancel-edit-btn")
    end

    # team-view.EDIT_ROLE.2
    test "edit modal renders a role dropdown", %{conn: conn, team: team, other: other} do
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#edit-btn-#{other.id}") |> render_click()

      assert has_element?(view, "#edit-role-form select")
    end

    # team-view.EDIT_ROLE.3
    test "saving a role updates the member's role immediately", %{
      conn: conn,
      team: team,
      other: other
    } do
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#edit-btn-#{other.id}") |> render_click()

      view
      |> form("#edit-role-form", %{"edit" => %{"role" => "readonly"}})
      |> render_submit()

      refute has_element?(view, "#edit-role-modal")
      assert has_element?(view, "#member-#{other.id}", "readonly")
    end

    # team-view.MEMBERS.3-2
    test "shows error when owner tries to edit their own role (self-demotion guard)", %{
      conn: conn,
      user: user,
      team: team
    } do
      other_owner = user_fixture()
      user_team_role_fixture(team, other_owner, %{title: "owner"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#edit-btn-#{user.id}") |> render_click()

      view
      |> form("#edit-role-form", %{"edit" => %{"role" => "developer"}})
      |> render_submit()

      assert has_element?(view, "#edit-error-msg")
    end
  end

  describe "delete member modal" do
    setup :register_and_log_in_user

    setup %{user: user} do
      {team, _role} = create_team_with_owner(user)
      other = user_fixture()
      user_team_role_fixture(team, other, %{title: "developer"})
      %{team: team, other: other}
    end

    # team-view.DELETE_ROLE.1
    test "clicking delete button opens the delete modal", %{conn: conn, team: team, other: other} do
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      refute has_element?(view, "#delete-member-modal")
      view |> element("#delete-btn-#{other.id}") |> render_click()
      assert has_element?(view, "#delete-member-modal")
    end

    # team-view.DELETE_ROLE.1
    test "delete modal renders Delete and Cancel buttons", %{conn: conn, team: team, other: other} do
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#delete-btn-#{other.id}") |> render_click()

      assert has_element?(view, "#confirm-delete-btn")
      assert has_element?(view, "#cancel-delete-btn")
    end

    # team-view.DELETE_ROLE.2
    test "delete modal shows warning about access and token revocation", %{
      conn: conn,
      team: team,
      other: other
    } do
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#delete-btn-#{other.id}") |> render_click()

      assert has_element?(view, "#delete-member-modal", "access")
      assert has_element?(view, "#delete-member-modal", "tokens")
    end

    test "closing the delete modal hides it", %{conn: conn, team: team, other: other} do
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#delete-btn-#{other.id}") |> render_click()

      assert has_element?(view, "#delete-member-modal")
      view |> element("#cancel-delete-btn") |> render_click()
      refute has_element?(view, "#delete-member-modal")
    end

    # team-view.DELETE_ROLE.3
    test "confirming delete removes the member and revokes their tokens", %{
      conn: conn,
      team: team,
      other: other
    } do
      token = access_token_fixture(team, other)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#delete-btn-#{other.id}") |> render_click()
      view |> element("#confirm-delete-btn") |> render_click()

      refute has_element?(view, "#delete-member-modal")
      refute has_element?(view, "#member-#{other.id}")

      updated_token = Repo.get!(Acai.Teams.AccessToken, token.id)
      assert not is_nil(updated_token.revoked_at)
    end

    # team-view.DELETE_ROLE.4
    test "shows error when trying to delete the last owner", %{conn: conn, user: user, team: team} do
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      view |> element("#delete-btn-#{user.id}") |> render_click()
      view |> element("#confirm-delete-btn") |> render_click()

      assert has_element?(view, "#delete-error-msg")
      assert has_element?(view, "#member-#{user.id}")
    end
  end
end
