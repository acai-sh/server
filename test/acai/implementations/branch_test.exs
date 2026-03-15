defmodule Acai.Implementations.BranchTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Implementations.Branch

  describe "changeset/2" do
    # data-model.BRANCHES.6: team_id is required
    test "valid with required fields" do
      team = team_fixture()

      attrs = %{
        repo_uri: "github.com/acai-sh/server",
        branch_name: "main",
        last_seen_commit: "abc123def456789",
        team_id: team.id
      }

      cs = Branch.changeset(%Branch{}, attrs)
      assert cs.valid?
    end

    # data-model.BRANCHES.2
    # data-model.BRANCHES.3
    # data-model.BRANCHES.4
    # data-model.BRANCHES.6
    test "invalid without required fields" do
      cs = Branch.changeset(%Branch{}, %{})
      refute cs.valid?
      assert %{repo_uri: [_ | _]} = errors_on(cs)
      assert %{branch_name: [_ | _]} = errors_on(cs)
      assert %{last_seen_commit: [_ | _]} = errors_on(cs)
      assert %{team_id: [_ | _]} = errors_on(cs)
    end

    # data-model.BRANCHES.1
    test "uses UUIDv7 primary key" do
      assert Branch.__schema__(:primary_key) == [:id]
      assert Branch.__schema__(:type, :id) == Acai.UUIDv7
    end

    # data-model.BRANCHES.5
    test "accepts last_seen_commit as string" do
      team = team_fixture()

      attrs = %{
        repo_uri: "github.com/acai-sh/server",
        branch_name: "main",
        last_seen_commit: "a" |> String.duplicate(40),
        team_id: team.id
      }

      cs = Branch.changeset(%Branch{}, attrs)
      assert cs.valid?
    end
  end

  describe "database constraints" do
    # data-model.BRANCHES.6-1: Composite unique on (team_id, repo_uri, branch_name)
    test "composite unique constraint on (team_id, repo_uri, branch_name)" do
      team = team_fixture()

      attrs = %{
        repo_uri: "github.com/acai-sh/server",
        branch_name: "main",
        last_seen_commit: "abc123def456789",
        team_id: team.id
      }

      # First branch should succeed
      {:ok, _} =
        Branch.changeset(%Branch{}, attrs)
        |> Acai.Repo.insert()

      # Second branch with same team_id, repo_uri and branch_name should fail
      {:error, cs} =
        Branch.changeset(%Branch{}, attrs)
        |> Acai.Repo.insert()

      assert %{team_id: [_ | _]} = errors_on(cs)
    end

    test "allows same repo_uri with different branch_name within same team" do
      team = team_fixture()

      attrs = %{
        repo_uri: "github.com/acai-sh/server",
        branch_name: "main",
        last_seen_commit: "abc123def456789",
        team_id: team.id
      }

      {:ok, _} =
        Branch.changeset(%Branch{}, attrs)
        |> Acai.Repo.insert()

      {:ok, _} =
        Branch.changeset(%Branch{}, %{attrs | branch_name: "develop"})
        |> Acai.Repo.insert()
    end

    test "allows different repo_uri with same branch_name within same team" do
      team = team_fixture()

      attrs = %{
        repo_uri: "github.com/acai-sh/server",
        branch_name: "main",
        last_seen_commit: "abc123def456789",
        team_id: team.id
      }

      {:ok, _} =
        Branch.changeset(%Branch{}, attrs)
        |> Acai.Repo.insert()

      {:ok, _} =
        Branch.changeset(%Branch{}, %{attrs | repo_uri: "github.com/other/repo"})
        |> Acai.Repo.insert()
    end

    test "allows same repo_uri and branch_name across different teams" do
      team1 = team_fixture()
      team2 = team_fixture()

      attrs1 = %{
        repo_uri: "github.com/acai-sh/server",
        branch_name: "main",
        last_seen_commit: "abc123def456789",
        team_id: team1.id
      }

      attrs2 = %{
        repo_uri: "github.com/acai-sh/server",
        branch_name: "main",
        last_seen_commit: "abc123def456789",
        team_id: team2.id
      }

      {:ok, _} =
        Branch.changeset(%Branch{}, attrs1)
        |> Acai.Repo.insert()

      # Same repo/branch but different team should succeed
      {:ok, _} =
        Branch.changeset(%Branch{}, attrs2)
        |> Acai.Repo.insert()
    end
  end
end
