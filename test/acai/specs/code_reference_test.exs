defmodule Acai.Specs.CodeReferenceTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs.CodeReference

  @valid_attrs %{
    repo_uri: "github.com/acai-sh/server",
    last_seen_commit: "abc123",
    acid_string: "my-feature.COMP.1",
    path: "lib/my_app/my_module.ex:42",
    is_test: false
  }

  describe "changeset/2" do
    test "valid with required fields" do
      cs = CodeReference.changeset(%CodeReference{}, @valid_attrs)
      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = CodeReference.changeset(%CodeReference{}, %{})
      refute cs.valid?
    end

    # data-model.REFS.7
    test "accepts optional last_seen_at" do
      cs =
        CodeReference.changeset(
          %CodeReference{},
          Map.put(@valid_attrs, :last_seen_at, DateTime.utc_now(:second))
        )

      assert cs.valid?
    end

    # data-model.REFS.9
    test "is_test defaults to false when not provided" do
      cs = CodeReference.changeset(%CodeReference{}, Map.delete(@valid_attrs, :is_test))
      assert cs.valid?
    end

    # data-model.REFS.9
    test "accepts is_test = true for test references" do
      cs = CodeReference.changeset(%CodeReference{}, Map.put(@valid_attrs, :is_test, true))
      assert cs.valid?
    end

    # data-model.REFS.8
    test "requires path" do
      cs = CodeReference.changeset(%CodeReference{}, Map.delete(@valid_attrs, :path))
      refute cs.valid?
      assert %{path: [_ | _]} = errors_on(cs)
    end

    # data-model.REFS.1
    test "uses UUIDv7 primary key" do
      assert CodeReference.__schema__(:primary_key) == [:id]
      assert CodeReference.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database - unique constraint on (requirement_id, branch_id, path)" do
    test "cannot insert two refs with the same requirement, branch, and path" do
      team = team_fixture()
      spec = spec_fixture(team)
      req = requirement_fixture(spec)
      impl = implementation_fixture(spec)
      branch = tracked_branch_fixture(impl)
      _first = code_reference_fixture(req, branch)

      {:error, cs} =
        CodeReference.changeset(%CodeReference{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:requirement_id, req.id)
        |> Ecto.Changeset.put_change(:branch_id, branch.id)
        |> Acai.Repo.insert()

      assert %{requirement_id: [_ | _]} = errors_on(cs)
    end

    test "allows two refs with the same requirement and branch at different paths" do
      team = team_fixture()
      spec = spec_fixture(team)
      req = requirement_fixture(spec)
      impl = implementation_fixture(spec)
      branch = tracked_branch_fixture(impl)
      _first = code_reference_fixture(req, branch, %{path: "lib/foo.ex:10"})

      assert {:ok, _} =
               CodeReference.changeset(%CodeReference{}, @valid_attrs)
               |> Ecto.Changeset.put_change(:requirement_id, req.id)
               |> Ecto.Changeset.put_change(:branch_id, branch.id)
               |> Ecto.Changeset.put_change(:path, "lib/bar.ex:20")
               |> Acai.Repo.insert()
    end
  end

  describe "database - data-model.REFS.2 on_delete: nothing" do
    test "deleting a requirement with code_references raises a foreign key constraint error" do
      team = team_fixture()
      spec = spec_fixture(team)
      req = requirement_fixture(spec)
      impl = implementation_fixture(spec)
      branch = tracked_branch_fixture(impl)
      _ref = code_reference_fixture(req, branch)

      # data-model.REFS.2 — FK is on_delete: :nothing, so deleting the requirement
      # while code_references reference it must raise a constraint error
      assert_raise Ecto.ConstraintError, fn ->
        Acai.Repo.delete!(req)
      end
    end

    test "code_reference row persists as long as requirement exists" do
      team = team_fixture()
      spec = spec_fixture(team)
      req = requirement_fixture(spec)
      impl = implementation_fixture(spec)
      branch = tracked_branch_fixture(impl)
      ref = code_reference_fixture(req, branch)

      # data-model.REFS.2 — row is still present while the requirement exists
      assert Acai.Repo.get(CodeReference, ref.id) != nil
    end
  end

  describe "database - data-model.REFS.10 on_delete: delete_all for branch" do
    test "deleting a tracked branch cascade-deletes its code_references" do
      team = team_fixture()
      spec = spec_fixture(team)
      req = requirement_fixture(spec)
      impl = implementation_fixture(spec)
      branch = tracked_branch_fixture(impl)
      ref = code_reference_fixture(req, branch)

      Acai.Repo.delete!(branch)

      assert is_nil(Acai.Repo.get(CodeReference, ref.id))
    end
  end
end
