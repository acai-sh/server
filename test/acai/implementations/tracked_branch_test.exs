defmodule Acai.Implementations.TrackedBranchTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Implementations.TrackedBranch

  @valid_attrs %{
    repo_uri: "github.com/acai-sh/server",
    branch_name: "main",
    last_seen_commit: "abc123def456789"
  }

  describe "changeset/2" do
    test "valid with required fields" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      attrs = @valid_attrs |> Map.put(:implementation_id, impl.id)
      cs = TrackedBranch.changeset(%TrackedBranch{}, attrs)
      assert cs.valid?
    end

    # data-model.BRANCHES.3
    # data-model.BRANCHES.4
    # data-model.BRANCHES.5
    test "invalid without required fields" do
      cs = TrackedBranch.changeset(%TrackedBranch{}, %{})
      refute cs.valid?
      assert %{repo_uri: [_ | _]} = errors_on(cs)
      assert %{branch_name: [_ | _]} = errors_on(cs)
      assert %{last_seen_commit: [_ | _]} = errors_on(cs)
      assert %{implementation_id: [_ | _]} = errors_on(cs)
    end

    # data-model.BRANCHES.1
    test "uses UUIDv7 primary key" do
      assert TrackedBranch.__schema__(:primary_key) == [:id]
      assert TrackedBranch.__schema__(:type, :id) == Acai.UUIDv7
    end

    # data-model.BRANCHES.5
    test "accepts last_seen_commit as string" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      attrs =
        @valid_attrs
        |> Map.put(:last_seen_commit, "a" |> String.duplicate(40))
        |> Map.put(:implementation_id, impl.id)

      cs = TrackedBranch.changeset(%TrackedBranch{}, attrs)

      assert cs.valid?
    end
  end

  describe "database constraints" do
    # data-model.BRANCHES.6
    test "composite unique constraint on (implementation_id, repo_uri)" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)
      tracked_branch_fixture(impl, %{repo_uri: "github.com/acai-sh/server"})

      attrs = @valid_attrs |> Map.put(:implementation_id, impl.id)

      {:error, cs} =
        TrackedBranch.changeset(%TrackedBranch{}, attrs)
        |> Acai.Repo.insert()

      assert %{implementation_id: [_ | _]} = errors_on(cs)
    end
  end
end
