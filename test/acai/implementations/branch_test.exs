defmodule Acai.Implementations.BranchTest do
  use Acai.DataCase, async: true

  alias Acai.Implementations.Branch

  @valid_attrs %{
    repo_uri: "github.com/acai-sh/server",
    branch_name: "main",
    last_seen_commit: "abc123def456789"
  }

  describe "changeset/2" do
    test "valid with required fields" do
      cs = Branch.changeset(%Branch{}, @valid_attrs)
      assert cs.valid?
    end

    # data-model.BRANCHES.3
    # data-model.BRANCHES.4
    # data-model.BRANCHES.5
    test "invalid without required fields" do
      cs = Branch.changeset(%Branch{}, %{})
      refute cs.valid?
      assert %{repo_uri: [_ | _]} = errors_on(cs)
      assert %{branch_name: [_ | _]} = errors_on(cs)
      assert %{last_seen_commit: [_ | _]} = errors_on(cs)
    end

    # data-model.BRANCHES.1
    test "uses UUIDv7 primary key" do
      assert Branch.__schema__(:primary_key) == [:id]
      assert Branch.__schema__(:type, :id) == Acai.UUIDv7
    end

    # data-model.BRANCHES.5
    test "accepts last_seen_commit as string" do
      attrs = %{@valid_attrs | last_seen_commit: "a" |> String.duplicate(40)}
      cs = Branch.changeset(%Branch{}, attrs)
      assert cs.valid?
    end
  end

  describe "database constraints" do
    # data-model.BRANCHES.8
    test "composite unique constraint on (repo_uri, branch_name)" do
      # First branch should succeed
      {:ok, _} =
        Branch.changeset(%Branch{}, @valid_attrs)
        |> Acai.Repo.insert()

      # Second branch with same repo_uri and branch_name should fail
      {:error, cs} =
        Branch.changeset(%Branch{}, @valid_attrs)
        |> Acai.Repo.insert()

      assert %{repo_uri: [_ | _]} = errors_on(cs)
    end

    test "allows same repo_uri with different branch_name" do
      {:ok, _} =
        Branch.changeset(%Branch{}, @valid_attrs)
        |> Acai.Repo.insert()

      {:ok, _} =
        Branch.changeset(%Branch{}, %{@valid_attrs | branch_name: "develop"})
        |> Acai.Repo.insert()
    end

    test "allows different repo_uri with same branch_name" do
      {:ok, _} =
        Branch.changeset(%Branch{}, @valid_attrs)
        |> Acai.Repo.insert()

      {:ok, _} =
        Branch.changeset(%Branch{}, %{@valid_attrs | repo_uri: "github.com/other/repo"})
        |> Acai.Repo.insert()
    end
  end
end
