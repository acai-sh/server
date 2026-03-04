defmodule Acai.Teams.UserTeamRoleTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures
  import Acai.AccountsFixtures

  alias Acai.Teams.UserTeamRole

  describe "changeset/2" do
    # data-model.team-roles.3
    test "valid with title owner" do
      cs = UserTeamRole.changeset(%UserTeamRole{}, %{title: "owner"})
      assert cs.valid?
    end

    # team-roles.SCOPES.1
    test "valid with title developer" do
      cs = UserTeamRole.changeset(%UserTeamRole{}, %{title: "developer"})
      assert cs.valid?
    end

    test "valid with title readonly" do
      cs = UserTeamRole.changeset(%UserTeamRole{}, %{title: "readonly"})
      assert cs.valid?
    end

    test "invalid without a title" do
      cs = UserTeamRole.changeset(%UserTeamRole{}, %{})
      refute cs.valid?
      assert %{title: [_ | _]} = errors_on(cs)
    end

    # team-roles.SCOPES.2
    test "invalid with an unrecognised role title" do
      cs = UserTeamRole.changeset(%UserTeamRole{}, %{title: "superadmin"})
      refute cs.valid?
      assert %{title: [_ | _]} = errors_on(cs)
    end

    test "invalid with an empty title string" do
      cs = UserTeamRole.changeset(%UserTeamRole{}, %{title: ""})
      refute cs.valid?
      assert %{title: [_ | _]} = errors_on(cs)
    end
  end

  describe "database constraints" do
    # data-model.ROLES - unique (team_id, user_id)
    test "prevents duplicate role assignments for the same user and team" do
      user = user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "readonly"})

      {:error, cs} =
        UserTeamRole.changeset(%UserTeamRole{}, %{title: "developer"})
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Acai.Repo.insert()

      assert %{team_id: [_ | _]} = errors_on(cs)
    end

    # data-model.ROLES - no primary key
    test "schema has no primary key" do
      assert UserTeamRole.__schema__(:primary_key) == []
    end
  end
end
