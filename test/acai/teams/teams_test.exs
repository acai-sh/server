defmodule Acai.TeamsTest do
  use Acai.DataCase, async: true

  import Ecto.Query
  import Acai.AccountsFixtures
  import Acai.DataModelFixtures

  alias Acai.Teams
  alias Acai.Teams.AccessToken
  alias Acai.Accounts.Scope
  alias Acai.Repo

  # Drain any pending email messages from the test process mailbox
  defp flush_emails do
    receive do
      {:email, _} -> flush_emails()
    after
      0 -> :ok
    end
  end

  describe "update_member_role/3" do
    setup do
      owner = user_fixture()
      other_owner = user_fixture()
      developer_user = user_fixture()
      readonly_user = user_fixture()

      team = team_fixture()

      owner_role = user_team_role_fixture(team, owner, %{title: "owner"})
      other_owner_role = user_team_role_fixture(team, other_owner, %{title: "owner"})
      developer_role = user_team_role_fixture(team, developer_user, %{title: "developer"})
      readonly_role = user_team_role_fixture(team, readonly_user, %{title: "readonly"})

      scope = Scope.for_user(owner)

      %{
        scope: scope,
        owner: owner,
        owner_role: owner_role,
        other_owner_role: other_owner_role,
        developer_role: developer_role,
        readonly_role: readonly_role,
        team: team
      }
    end

    # ROLES.SCOPES.7
    test "returns :self_demotion when an owner attempts to change their own role", %{
      scope: scope,
      owner_role: owner_role
    } do
      assert {:error, :self_demotion} = Teams.update_member_role(scope, owner_role, "developer")
    end

    # ROLES.MODULE.3
    test "returns :last_owner when acting user tries to demote the sole remaining owner", %{
      scope: scope,
      other_owner_role: other_owner_role,
      owner_role: owner_role,
      team: team
    } do
      # Remove the acting owner's record so other_owner is the only owner left
      Acai.Repo.delete_all(
        from r in Acai.Teams.UserTeamRole,
          where: r.team_id == ^team.id and r.user_id == ^owner_role.user_id
      )

      assert {:error, :last_owner} =
               Teams.update_member_role(scope, other_owner_role, "developer")
    end

    # ROLES.SCOPES.7 — owner CAN demote another owner when multiple owners exist
    test "successfully demotes another owner to developer when multiple owners exist", %{
      scope: scope,
      other_owner_role: other_owner_role
    } do
      assert {:ok, updated} = Teams.update_member_role(scope, other_owner_role, "developer")
      assert updated.title == "developer"
    end

    # Happy path — promote readonly to developer
    test "owner can promote a readonly member to developer", %{
      scope: scope,
      readonly_role: readonly_role
    } do
      assert {:ok, updated} = Teams.update_member_role(scope, readonly_role, "developer")
      assert updated.title == "developer"
    end

    # Happy path — demote developer to readonly
    test "owner can demote a developer to readonly", %{
      scope: scope,
      developer_role: developer_role
    } do
      assert {:ok, updated} = Teams.update_member_role(scope, developer_role, "readonly")
      assert updated.title == "readonly"
    end

    # Validates that the new title must be a valid role
    test "returns changeset error when new role title is invalid", %{
      scope: scope,
      developer_role: developer_role
    } do
      assert {:error, changeset} = Teams.update_member_role(scope, developer_role, "superadmin")
      assert %{title: [_ | _]} = errors_on(changeset)
    end
  end

  describe "list_team_members/1" do
    setup do
      owner = user_fixture()
      developer_user = user_fixture()
      team = team_fixture()

      owner_role = user_team_role_fixture(team, owner, %{title: "owner"})
      dev_role = user_team_role_fixture(team, developer_user, %{title: "developer"})

      %{
        team: team,
        owner: owner,
        developer_user: developer_user,
        owner_role: owner_role,
        dev_role: dev_role
      }
    end

    # TEAM.MEMBERS.1
    test "returns all members for the team", %{
      team: team,
      owner: owner,
      developer_user: developer_user
    } do
      members = Teams.list_team_members(team)
      user_ids = Enum.map(members, & &1.user_id)

      assert owner.id in user_ids
      assert developer_user.id in user_ids
    end

    # TEAM.MEMBERS.1
    test "preloads the user association", %{team: team} do
      members = Teams.list_team_members(team)
      assert Enum.all?(members, fn r -> not is_nil(r.user) and r.user.email end)
    end

    test "does not return members from other teams", %{team: team} do
      other_team = team_fixture()
      other_user = user_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})

      members = Teams.list_team_members(team)
      user_ids = Enum.map(members, & &1.user_id)
      refute other_user.id in user_ids
    end
  end

  describe "invite_member/4" do
    setup do
      team = team_fixture()
      %{team: team}
    end

    # TEAM.INVITE.3-2
    test "creates a new user record when the email doesn't exist yet", %{team: team} do
      email = unique_user_email()

      assert {:ok, member} =
               Teams.invite_member(team, email, "developer", &"http://example.com/#{&1}")

      assert member.title == "developer"
      assert member.user.email == email
    end

    # TEAM.INVITE.3-4
    test "adds an existing user to the team immediately", %{team: team} do
      existing_user = user_fixture()

      assert {:ok, member} =
               Teams.invite_member(
                 team,
                 existing_user.email,
                 "developer",
                 &"http://example.com/#{&1}"
               )

      assert member.user_id == existing_user.id
    end

    # TEAM.INVITE.3-1
    test "returns :already_member when the user is already on the team", %{team: team} do
      existing_user = user_fixture()
      user_team_role_fixture(team, existing_user, %{title: "developer"})

      assert {:error, :already_member} =
               Teams.invite_member(
                 team,
                 existing_user.email,
                 "developer",
                 &"http://example.com/#{&1}"
               )
    end

    # TEAM.INVITE.2
    test "assigns the specified role to the invited member", %{team: team} do
      email = unique_user_email()

      assert {:ok, member} =
               Teams.invite_member(team, email, "readonly", &"http://example.com/#{&1}")

      assert member.title == "readonly"
    end

    # TEAM.INVITE.3-3
    test "sends a magic-link confirmation email to a new (unconfirmed) user", %{team: team} do
      email = unique_user_email()

      assert {:ok, _member} =
               Teams.invite_member(team, email, "developer", &"http://example.com/#{&1}")

      assert_received {:email, sent_email}
      assert sent_email.subject =~ "Confirmation instructions"
      assert sent_email.to == [{email, email}] or match?([{_, ^email}], sent_email.to)
    end

    # TEAM.INVITE.3-3
    test "sends a notification email to an existing confirmed user", %{team: team} do
      existing_user = user_fixture()

      # Drain any emails sent during user_fixture setup (login instructions)
      flush_emails()

      assert {:ok, _member} =
               Teams.invite_member(
                 team,
                 existing_user.email,
                 "developer",
                 &"http://example.com/#{&1}"
               )

      assert_received {:email, sent_email}
      assert sent_email.subject =~ team.name
    end
  end

  describe "delete_team/1" do
    setup do
      team = team_fixture()
      %{team: team}
    end

    # TEAM_SETTINGS.DELETE.5
    test "deletes the team and returns {:ok, team}", %{team: team} do
      assert {:ok, deleted} = Teams.delete_team(team)
      assert deleted.id == team.id
      assert is_nil(Acai.Repo.get(Acai.Teams.Team, team.id))
    end

    # TEAM_SETTINGS.DELETE.5
    test "cascade-deletes associated member roles", %{team: team} do
      user = user_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      assert {:ok, _} = Teams.delete_team(team)

      roles =
        Acai.Repo.all(from r in Acai.Teams.UserTeamRole, where: r.team_id == ^team.id)

      assert roles == []
    end
  end

  describe "remove_member/2" do
    setup do
      owner = user_fixture()
      other_user = user_fixture()
      team = team_fixture()

      owner_role = user_team_role_fixture(team, owner, %{title: "owner"})
      other_role = user_team_role_fixture(team, other_user, %{title: "developer"})

      token = access_token_fixture(team, other_user)

      %{
        team: team,
        owner: owner,
        owner_role: owner_role,
        other_user: other_user,
        other_role: other_role,
        token: token
      }
    end

    # TEAM.DELETE_ROLE.3
    test "revokes all access tokens for the removed user on that team", %{
      team: team,
      other_user: other_user,
      token: token
    } do
      assert {:ok, :removed} = Teams.remove_member(team, other_user.id)
      updated_token = Repo.get!(AccessToken, token.id)
      assert not is_nil(updated_token.revoked_at)
    end

    test "removes the user's team role", %{team: team, other_user: other_user} do
      assert {:ok, :removed} = Teams.remove_member(team, other_user.id)
      members = Teams.list_team_members(team)
      user_ids = Enum.map(members, & &1.user_id)
      refute other_user.id in user_ids
    end

    # TEAM.DELETE_ROLE.4
    test "returns :last_owner when trying to remove the sole owner", %{
      team: team,
      owner: owner
    } do
      assert {:error, :last_owner} = Teams.remove_member(team, owner.id)
    end

    test "can remove an owner when another owner exists", %{
      team: team,
      other_user: other_user
    } do
      # Promote other_user to owner
      Repo.update_all(
        from(r in Acai.Teams.UserTeamRole,
          where: r.team_id == ^team.id and r.user_id == ^other_user.id
        ),
        set: [title: "owner"]
      )

      # Now we can remove either owner since there are two
      assert {:ok, :removed} = Teams.remove_member(team, other_user.id)
    end
  end
end
