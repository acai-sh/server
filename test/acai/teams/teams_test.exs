defmodule Acai.TeamsTest do
  use Acai.DataCase, async: true

  import Ecto.Query
  import Acai.AccountsFixtures
  import Acai.DataModelFixtures

  alias Acai.Teams
  alias Acai.Accounts.Scope

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
end
