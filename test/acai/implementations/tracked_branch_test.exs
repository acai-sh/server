defmodule Acai.Implementations.TrackedBranchTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Implementations.TrackedBranch

  @valid_attrs %{
    repo_uri: "github.com/acai-sh/server",
    branch_name: "main"
  }

  describe "changeset/2" do
    test "valid with required fields" do
      cs = TrackedBranch.changeset(%TrackedBranch{}, @valid_attrs)
      assert cs.valid?
    end

    # DATA.BRANCHES.3
    # DATA.BRANCHES.4
    test "invalid without required fields" do
      cs = TrackedBranch.changeset(%TrackedBranch{}, %{})
      refute cs.valid?
    end

    # DATA.BRANCHES.1
    test "uses UUIDv7 primary key" do
      assert TrackedBranch.__schema__(:primary_key) == [:id]
      assert TrackedBranch.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database constraints" do
    # DATA.BRANCHES.5
    test "composite unique constraint on (implementation_id, repo_uri)" do
      team = team_fixture()
      spec = spec_fixture(team)
      impl = implementation_fixture(spec)
      tracked_branch_fixture(impl, %{repo_uri: "github.com/acai-sh/server"})

      {:error, cs} =
        TrackedBranch.changeset(%TrackedBranch{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:implementation_id, impl.id)
        |> Acai.Repo.insert()

      assert %{implementation_id: [_ | _]} = errors_on(cs)
    end
  end
end
