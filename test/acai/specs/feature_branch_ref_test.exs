defmodule Acai.Specs.FeatureBranchRefTest do
  @moduledoc """
  Tests for the FeatureBranchRef schema.

  ACIDs:
  - data-model.FEATURE_BRANCH_REFS.1: UUIDv7 Primary Key
  - data-model.FEATURE_BRANCH_REFS.2: branch_id FK to branches
  - data-model.FEATURE_BRANCH_REFS.3: feature_name matching spec
  - data-model.FEATURE_BRANCH_REFS.3-1: feature_name URL-safe validation
  - data-model.FEATURE_BRANCH_REFS.4: refs JSONB column
  - data-model.FEATURE_BRANCH_REFS.4-1: refs keyed by ACID
  - data-model.FEATURE_BRANCH_REFS.4-3: ref objects contain path, is_test
  - data-model.FEATURE_BRANCH_REFS.6: commit field
  - data-model.FEATURE_BRANCH_REFS.7: pushed_at field
  - data-model.FEATURE_BRANCH_REFS.8: Unique constraint on (branch_id, feature_name)
  """
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs.FeatureBranchRef

  describe "changeset/2" do
    test "valid with all required fields" do
      team = team_fixture()
      branch = branch_fixture(team)

      attrs = %{
        refs: %{
          "feature.COMP.1" => [
            %{
              "path" => "lib/my_app/module.ex:42",
              "is_test" => false
            }
          ]
        },
        commit: "abc123def456",
        pushed_at: DateTime.utc_now(),
        feature_name: "test-feature",
        branch_id: branch.id
      }

      cs = FeatureBranchRef.changeset(%FeatureBranchRef{}, attrs)

      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = FeatureBranchRef.changeset(%FeatureBranchRef{}, %{})
      refute cs.valid?
      # refs has default value %{}, so other fields show errors
      assert %{commit: [_ | _]} = errors_on(cs)
      assert %{pushed_at: [_ | _]} = errors_on(cs)
      assert %{branch_id: [_ | _]} = errors_on(cs)
      assert %{feature_name: [_ | _]} = errors_on(cs)
    end

    # data-model.FEATURE_BRANCH_REFS.1
    test "uses UUIDv7 primary key" do
      assert FeatureBranchRef.__schema__(:primary_key) == [:id]
      assert FeatureBranchRef.__schema__(:type, :id) == Acai.UUIDv7
    end

    # data-model.FEATURE_BRANCH_REFS.4
    test "accepts empty refs map" do
      team = team_fixture()
      branch = branch_fixture(team)

      attrs = %{
        refs: %{},
        commit: "abc123",
        pushed_at: DateTime.utc_now(),
        feature_name: "test-feature",
        branch_id: branch.id
      }

      cs = FeatureBranchRef.changeset(%FeatureBranchRef{}, attrs)

      assert cs.valid?
    end

    # data-model.FEATURE_BRANCH_REFS.4-2
    test "accepts multiple refs per ACID" do
      team = team_fixture()
      branch = branch_fixture(team)

      attrs = %{
        refs: %{
          "feature.COMP.1" => [
            %{"path" => "lib/a.ex:1", "is_test" => false},
            %{"path" => "lib/b.ex:2", "is_test" => false}
          ]
        },
        commit: "abc123",
        pushed_at: DateTime.utc_now(),
        feature_name: "test-feature",
        branch_id: branch.id
      }

      cs = FeatureBranchRef.changeset(%FeatureBranchRef{}, attrs)

      assert cs.valid?
    end

    # data-model.FEATURE_BRANCH_REFS.3-1
    test "feature_name must be url-safe" do
      team = team_fixture()
      branch = branch_fixture(team)

      attrs = %{
        refs: %{},
        commit: "abc123",
        pushed_at: DateTime.utc_now(),
        feature_name: "invalid feature name!",
        branch_id: branch.id
      }

      cs = FeatureBranchRef.changeset(%FeatureBranchRef{}, attrs)

      refute cs.valid?
      assert %{feature_name: [_ | _]} = errors_on(cs)
    end
  end

  describe "database constraint: FEATURE_BRANCH_REFS.8 (branch_id, feature_name)" do
    test "enforces composite unique constraint" do
      team = team_fixture()
      branch = branch_fixture(team)

      {:ok, _} =
        FeatureBranchRef.changeset(%FeatureBranchRef{}, %{
          refs: %{},
          commit: "abc123",
          pushed_at: DateTime.utc_now(),
          feature_name: "test-feature",
          branch_id: branch.id
        })
        |> Acai.Repo.insert()

      {:error, cs} =
        FeatureBranchRef.changeset(%FeatureBranchRef{}, %{
          refs: %{"a" => [%{"path" => "lib/foo.ex"}]},
          commit: "def456",
          pushed_at: DateTime.utc_now(),
          feature_name: "test-feature",
          branch_id: branch.id
        })
        |> Acai.Repo.insert()

      assert %{branch_id: [_ | _]} = errors_on(cs)
    end

    test "allows same feature_name across different branches" do
      team = team_fixture()
      branch1 = branch_fixture(team, %{branch_name: "main"})
      branch2 = branch_fixture(team, %{branch_name: "develop"})

      {:ok, _} =
        FeatureBranchRef.changeset(%FeatureBranchRef{}, %{
          refs: %{},
          commit: "abc123",
          pushed_at: DateTime.utc_now(),
          feature_name: "test-feature",
          branch_id: branch1.id
        })
        |> Acai.Repo.insert()

      {:ok, _} =
        FeatureBranchRef.changeset(%FeatureBranchRef{}, %{
          refs: %{},
          commit: "abc123",
          pushed_at: DateTime.utc_now(),
          feature_name: "test-feature",
          branch_id: branch2.id
        })
        |> Acai.Repo.insert()
    end

    test "allows different feature_names on same branch" do
      team = team_fixture()
      branch = branch_fixture(team)

      {:ok, _} =
        FeatureBranchRef.changeset(%FeatureBranchRef{}, %{
          refs: %{},
          commit: "abc123",
          pushed_at: DateTime.utc_now(),
          feature_name: "feature-a",
          branch_id: branch.id
        })
        |> Acai.Repo.insert()

      {:ok, _} =
        FeatureBranchRef.changeset(%FeatureBranchRef{}, %{
          refs: %{},
          commit: "abc123",
          pushed_at: DateTime.utc_now(),
          feature_name: "feature-b",
          branch_id: branch.id
        })
        |> Acai.Repo.insert()
    end
  end

  describe "refs JSONB format" do
    test "stores refs keyed by ACID" do
      team = team_fixture()
      branch = branch_fixture(team)

      attrs = %{
        refs: %{
          "my-feature.COMP.1" => [
            %{"path" => "lib/foo.ex:42", "is_test" => false}
          ],
          "my-feature.COMP.2" => [
            %{"path" => "test/foo_test.exs:10", "is_test" => true}
          ]
        },
        commit: "abc123",
        pushed_at: DateTime.utc_now(),
        feature_name: "my-feature",
        branch_id: branch.id
      }

      {:ok, ref} =
        FeatureBranchRef.changeset(%FeatureBranchRef{}, attrs)
        |> Acai.Repo.insert()

      assert Map.has_key?(ref.refs, "my-feature.COMP.1")
      assert Map.has_key?(ref.refs, "my-feature.COMP.2")
    end

    test "ref objects contain path and is_test" do
      team = team_fixture()
      branch = branch_fixture(team)

      attrs = %{
        refs: %{
          "my-feature.COMP.1" => [
            %{"path" => "lib/foo.ex:42", "is_test" => false},
            %{"path" => "test/foo_test.exs:10", "is_test" => true}
          ]
        },
        commit: "abc123",
        pushed_at: DateTime.utc_now(),
        feature_name: "my-feature",
        branch_id: branch.id
      }

      {:ok, ref} =
        FeatureBranchRef.changeset(%FeatureBranchRef{}, attrs)
        |> Acai.Repo.insert()

      [first_ref, second_ref] = ref.refs["my-feature.COMP.1"]
      assert first_ref["path"] == "lib/foo.ex:42"
      assert first_ref["is_test"] == false
      assert second_ref["path"] == "test/foo_test.exs:10"
      assert second_ref["is_test"] == true
    end
  end
end
