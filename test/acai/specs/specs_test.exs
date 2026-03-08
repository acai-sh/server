defmodule Acai.SpecsTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs

  # Shared setup: team -> spec -> requirement -> implementation -> branch
  defp setup_ref_chain(_ctx \\ %{}) do
    team = team_fixture()
    spec = spec_fixture(team)
    req = requirement_fixture(spec)
    impl = implementation_fixture(spec)
    branch = tracked_branch_fixture(impl)
    %{team: team, spec: spec, req: req, impl: impl, branch: branch}
  end

  describe "batch_count_requirements/1" do
    # feature-view.PERFORMANCE.1
    test "returns empty map for empty list" do
      assert Specs.batch_count_requirements([]) == %{}
    end

    test "returns map of spec_id => requirement count" do
      team = team_fixture()
      spec1 = spec_fixture(team)

      spec2 =
        spec_fixture(team, %{feature_name: "other-feature", path: "features/other/feature.yaml"})

      requirement_fixture(spec1)
      requirement_fixture(spec1, %{local_id: "2"})
      requirement_fixture(spec2)

      counts = Specs.batch_count_requirements([spec1, spec2])

      assert Map.get(counts, spec1.id) == 2
      assert Map.get(counts, spec2.id) == 1
    end

    test "returns no entry for specs with no requirements" do
      team = team_fixture()
      spec = spec_fixture(team)

      counts = Specs.batch_count_requirements([spec])

      assert Map.get(counts, spec.id) == nil
    end
  end

  describe "get_requirement!/1" do
    # requirement-details.DRAWER.5-1
    test "returns the requirement by id" do
      %{req: req} = setup_ref_chain()
      assert Specs.get_requirement!(req.id).id == req.id
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Specs.get_requirement!(Acai.UUIDv7.autogenerate())
      end
    end
  end

  describe "list_code_references/1" do
    test "returns empty list when no refs exist" do
      %{req: req} = setup_ref_chain()
      assert Specs.list_code_references(req) == []
    end

    test "returns refs for the given requirement" do
      %{req: req, branch: branch} = setup_ref_chain()

      {:ok, ref} =
        Specs.create_code_reference(req, branch, %{
          repo_uri: "github.com/acai-sh/server",
          last_seen_commit: "abc123",
          acid_string: "example-feature.COMP.1",
          path: "lib/my_app/foo.ex:10",
          is_test: false
        })

      assert [^ref] = Specs.list_code_references(req)
    end

    test "does not return refs belonging to a different requirement" do
      %{spec: spec, branch: branch, req: req} = setup_ref_chain()
      other_req = requirement_fixture(spec, %{local_id: "2"})

      {:ok, _other_ref} =
        Specs.create_code_reference(other_req, branch, %{
          repo_uri: "github.com/acai-sh/server",
          last_seen_commit: "abc123",
          acid_string: "example-feature.COMP.2",
          path: "lib/my_app/bar.ex:20",
          is_test: false
        })

      assert Specs.list_code_references(req) == []
    end
  end

  describe "get_code_reference!/1" do
    test "returns the code reference by id" do
      %{req: req, branch: branch} = setup_ref_chain()

      {:ok, ref} =
        Specs.create_code_reference(req, branch, %{
          repo_uri: "github.com/acai-sh/server",
          last_seen_commit: "abc123",
          acid_string: "example-feature.COMP.1",
          path: "lib/my_app/foo.ex:10",
          is_test: false
        })

      assert Specs.get_code_reference!(ref.id).id == ref.id
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Specs.get_code_reference!(Acai.UUIDv7.autogenerate())
      end
    end
  end

  describe "create_code_reference/3" do
    test "creates a code reference linked to the requirement and branch" do
      %{req: req, branch: branch} = setup_ref_chain()

      assert {:ok, ref} =
               Specs.create_code_reference(req, branch, %{
                 repo_uri: "github.com/acai-sh/server",
                 last_seen_commit: "abc123",
                 acid_string: "example-feature.COMP.1",
                 path: "lib/my_app/foo.ex:10",
                 is_test: false
               })

      assert ref.requirement_id == req.id
      assert ref.branch_id == branch.id
      assert ref.path == "lib/my_app/foo.ex:10"
      assert ref.is_test == false
    end

    test "creates a test reference when is_test is true" do
      %{req: req, branch: branch} = setup_ref_chain()

      assert {:ok, ref} =
               Specs.create_code_reference(req, branch, %{
                 repo_uri: "github.com/acai-sh/server",
                 last_seen_commit: "abc123",
                 acid_string: "example-feature.COMP.1",
                 path: "test/my_app/foo_test.exs:55",
                 is_test: true
               })

      assert ref.is_test == true
    end

    test "returns error changeset when attrs are invalid" do
      %{req: req, branch: branch} = setup_ref_chain()

      assert {:error, changeset} = Specs.create_code_reference(req, branch, %{})
      refute changeset.valid?
    end

    test "returns error on duplicate (requirement_id, branch_id, path)" do
      %{req: req, branch: branch} = setup_ref_chain()

      attrs = %{
        repo_uri: "github.com/acai-sh/server",
        last_seen_commit: "abc123",
        acid_string: "example-feature.COMP.1",
        path: "lib/my_app/foo.ex:10",
        is_test: false
      }

      assert {:ok, _} = Specs.create_code_reference(req, branch, attrs)
      assert {:error, cs} = Specs.create_code_reference(req, branch, attrs)
      assert %{requirement_id: [_ | _]} = errors_on(cs)
    end
  end

  describe "upsert_code_reference/3" do
    @attrs %{
      repo_uri: "github.com/acai-sh/server",
      last_seen_commit: "abc123",
      acid_string: "example-feature.COMP.1",
      path: "lib/my_app/foo.ex:10",
      is_test: false
    }

    test "inserts a new code reference when none exists" do
      %{req: req, branch: branch} = setup_ref_chain()

      assert {:ok, ref} = Specs.upsert_code_reference(req, branch, @attrs)
      assert ref.requirement_id == req.id
      assert ref.branch_id == branch.id
      assert ref.last_seen_commit == "abc123"
    end

    test "updates mutable fields on conflict without changing the id" do
      %{req: req, branch: branch} = setup_ref_chain()

      {:ok, original} = Specs.upsert_code_reference(req, branch, @attrs)

      updated_attrs = Map.merge(@attrs, %{last_seen_commit: "def456", is_test: true})
      {:ok, updated} = Specs.upsert_code_reference(req, branch, updated_attrs)

      # id is preserved
      assert updated.id == original.id
      # mutable fields are updated
      assert updated.last_seen_commit == "def456"
      assert updated.is_test == true
    end

    test "two different paths for the same requirement and branch are stored separately" do
      %{req: req, branch: branch} = setup_ref_chain()

      {:ok, _ref1} = Specs.upsert_code_reference(req, branch, @attrs)

      {:ok, _ref2} =
        Specs.upsert_code_reference(req, branch, Map.put(@attrs, :path, "lib/my_app/bar.ex:99"))

      assert length(Specs.list_code_references(req)) == 2
    end
  end

  describe "change_code_reference/2" do
    test "returns a changeset for a code reference" do
      %{req: req, branch: branch} = setup_ref_chain()
      ref = code_reference_fixture(req, branch)

      cs = Specs.change_code_reference(ref, %{last_seen_commit: "newcommit"})
      assert cs.changes == %{last_seen_commit: "newcommit"}
    end

    test "returns a blank changeset with no attrs" do
      %{req: req, branch: branch} = setup_ref_chain()
      ref = code_reference_fixture(req, branch)

      cs = Specs.change_code_reference(ref)
      assert cs.changes == %{}
    end
  end
end
