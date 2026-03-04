defmodule Acai.Teams.UserTeamRoleTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures
  import Acai.AccountsFixtures

  alias Acai.Teams.UserTeamRole

  describe "changeset/2" do
    # DATA.ROLES.3
    test "valid with a title" do
      cs = UserTeamRole.changeset(%UserTeamRole{}, %{title: "owner"})
      assert cs.valid?
    end

    test "invalid without a title" do
      cs = UserTeamRole.changeset(%UserTeamRole{}, %{})
      refute cs.valid?
      assert %{title: [_ | _]} = errors_on(cs)
    end
  end

  describe "database constraints" do
    # DATA.ROLES - unique (team_id, user_id)
    test "prevents duplicate role assignments for the same user and team" do
      user = user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "member"})

      {:error, cs} =
        UserTeamRole.changeset(%UserTeamRole{}, %{title: "admin"})
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Acai.Repo.insert()

      assert %{team_id: [_ | _]} = errors_on(cs)
    end

    # DATA.ROLES - no primary key
    test "schema has no primary key" do
      assert UserTeamRole.__schema__(:primary_key) == []
    end
  end
end
