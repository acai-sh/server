defmodule Acai.Teams.TeamTest do
  use Acai.DataCase, async: true

  alias Acai.Teams.Team

  describe "changeset/2" do
    # DATA.TEAMS.2
    test "valid with a URL-safe name" do
      cs = Team.changeset(%Team{}, %{name: "my-team_1"})
      assert cs.valid?
    end

    test "invalid without a name" do
      cs = Team.changeset(%Team{}, %{})
      refute cs.valid?
      assert %{name: [_ | _]} = errors_on(cs)
    end

    # DATA.TEAMS.2-1
    test "invalid when name contains spaces" do
      cs = Team.changeset(%Team{}, %{name: "my team"})
      refute cs.valid?
    end

    test "invalid when name contains special characters" do
      cs = Team.changeset(%Team{}, %{name: "my@team"})
      refute cs.valid?
    end

    # DATA.TEAMS.1
    test "uses UUIDv7 primary key" do
      assert Team.__schema__(:primary_key) == [:id]
      assert Team.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database constraints" do
    # DATA.TEAMS.2
    test "name must be unique (case-insensitive)" do
      import Acai.DataModelFixtures
      _team = team_fixture(%{name: "unique-team"})

      {:error, cs} =
        Team.changeset(%Team{}, %{name: "UNIQUE-TEAM"})
        |> Acai.Repo.insert()

      assert %{name: [_ | _]} = errors_on(cs)
    end

    # DATA.TEAMS.2-1
    test "name_url_safe check constraint fires for invalid chars" do
      {:error, cs} =
        %Team{}
        |> Team.changeset(%{name: "valid-name"})
        |> Ecto.Changeset.put_change(:name, "invalid name!")
        |> Acai.Repo.insert()

      assert cs.errors[:name] != nil
    end
  end
end
