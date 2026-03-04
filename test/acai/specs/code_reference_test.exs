defmodule Acai.Specs.CodeReferenceTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs.CodeReference

  @valid_attrs %{
    repo_uri: "github.com/acai-sh/server",
    branch_name: "main",
    last_seen_commit: "abc123",
    acid_string: "MYFEAT.COMP.1"
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

    # DATA.REFS.7
    test "accepts optional last_seen_at" do
      cs =
        CodeReference.changeset(
          %CodeReference{},
          Map.put(@valid_attrs, :last_seen_at, DateTime.utc_now(:second))
        )

      assert cs.valid?
    end

    # DATA.REFS.1
    test "uses UUIDv7 primary key" do
      assert CodeReference.__schema__(:primary_key) == [:id]
      assert CodeReference.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database - DATA.REFS.2 on_delete: nothing" do
    test "deleting a requirement with code_references raises a foreign key constraint error" do
      team = team_fixture()
      spec = spec_fixture(team)
      req = requirement_fixture(spec)
      _ref = code_reference_fixture(req)

      # DATA.REFS.2 — FK is on_delete: :nothing, so deleting the requirement
      # while code_references reference it must raise a constraint error
      assert_raise Ecto.ConstraintError, fn ->
        Acai.Repo.delete!(req)
      end
    end

    test "code_reference row persists as long as requirement exists" do
      team = team_fixture()
      spec = spec_fixture(team)
      req = requirement_fixture(spec)
      ref = code_reference_fixture(req)

      # DATA.REFS.2 — row is still present while the requirement exists
      assert Acai.Repo.get(CodeReference, ref.id) != nil
    end
  end
end
