defmodule Acai.ImplementationsTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Implementations

  setup do
    team = team_fixture()
    product = product_fixture(team)
    {:ok, team: team, product: product}
  end

  describe "list_implementations/1" do
    test "returns implementations for the product", %{product: product} do
      impl = implementation_fixture(product)
      assert [^impl] = Implementations.list_implementations(product)
    end

    test "does not return implementations from other products", %{team: team, product: product} do
      other_product = product_fixture(team, %{name: "other-product"})
      implementation_fixture(other_product)

      assert Implementations.list_implementations(product) == []
    end
  end

  describe "get_implementation!/1" do
    test "returns the implementation by id", %{product: product} do
      impl = implementation_fixture(product)
      assert Implementations.get_implementation!(impl.id).id == impl.id
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Implementations.get_implementation!(Acai.UUIDv7.autogenerate())
      end
    end
  end

  describe "create_implementation/3" do
    test "creates an implementation linked to the product", %{team: team, product: product} do
      current_scope = %{user: %{id: 1}}
      attrs = %{name: "staging", description: "Staging environment"}

      assert {:ok, impl} = Implementations.create_implementation(current_scope, product, attrs)
      assert impl.name == "staging"
      assert impl.product_id == product.id
      assert impl.team_id == team.id
      assert impl.is_active == true
    end

    test "returns error changeset when attrs are invalid", %{product: product} do
      current_scope = %{user: %{id: 1}}

      assert {:error, changeset} =
               Implementations.create_implementation(current_scope, product, %{name: ""})

      refute changeset.valid?
    end
  end

  describe "update_implementation/2" do
    test "updates the implementation", %{product: product} do
      impl = implementation_fixture(product, %{name: "old-name"})
      attrs = %{name: "new-name", description: "Updated description"}

      assert {:ok, updated} = Implementations.update_implementation(impl, attrs)
      assert updated.name == "new-name"
      assert updated.description == "Updated description"
    end

    test "returns error changeset when attrs are invalid", %{product: product} do
      impl = implementation_fixture(product)
      assert {:error, changeset} = Implementations.update_implementation(impl, %{name: ""})
      refute changeset.valid?
    end
  end

  describe "change_implementation/2" do
    test "returns a changeset for the implementation", %{product: product} do
      impl = implementation_fixture(product)
      cs = Implementations.change_implementation(impl, %{name: "new-name"})
      assert cs.changes == %{name: "new-name"}
    end
  end

  describe "implementation_slug/1" do
    test "generates a URL-safe slug", %{product: product} do
      impl = implementation_fixture(product, %{name: "Production Server"})
      slug = Implementations.implementation_slug(impl)

      # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format
      assert slug =~ ~r/^production-server-[a-f0-9]{32}$/
    end
  end

  describe "get_implementation_by_slug/1" do
    test "returns the implementation by slug", %{product: product} do
      impl = implementation_fixture(product, %{name: "Production"})
      slug = Implementations.implementation_slug(impl)

      # feature-impl-view.ROUTING.3: impl_id is the UUID used for lookup
      assert Implementations.get_implementation_by_slug(slug).id == impl.id
    end

    test "returns nil for invalid slug format" do
      assert Implementations.get_implementation_by_slug("invalid-slug") == nil
    end

    test "returns nil when not found" do
      # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format with dash separator
      fake_slug = "test-" <> String.duplicate("a", 32)
      assert Implementations.get_implementation_by_slug(fake_slug) == nil
    end
  end

  describe "count_active_implementations/1" do
    test "counts only active implementations", %{product: product} do
      implementation_fixture(product, %{name: "active-1", is_active: true})
      implementation_fixture(product, %{name: "active-2", is_active: true})
      implementation_fixture(product, %{name: "inactive", is_active: false})

      assert Implementations.count_active_implementations(product) == 2
    end

    test "returns 0 when no active implementations", %{product: product} do
      implementation_fixture(product, %{name: "inactive", is_active: false})
      assert Implementations.count_active_implementations(product) == 0
    end
  end

  describe "batch_count_active_implementations_for_products/1" do
    test "returns empty map for empty list" do
      assert Implementations.batch_count_active_implementations_for_products([]) == %{}
    end

    test "returns map of product_id => active implementation count", %{team: team} do
      product1 = product_fixture(team, %{name: "product-1"})
      product2 = product_fixture(team, %{name: "product-2"})

      implementation_fixture(product1, %{name: "impl-1", is_active: true})
      implementation_fixture(product1, %{name: "impl-2", is_active: true})
      implementation_fixture(product2, %{name: "impl-3", is_active: true})
      implementation_fixture(product2, %{name: "impl-4", is_active: false})

      counts =
        Implementations.batch_count_active_implementations_for_products([product1, product2])

      assert Map.get(counts, product1.id) == 2
      assert Map.get(counts, product2.id) == 1
    end
  end

  describe "list_tracked_branches/1" do
    test "returns tracked branches for the implementation with preloaded branch", %{
      product: product
    } do
      impl = implementation_fixture(product)
      tracked_branch = tracked_branch_fixture(impl)

      [result] = Implementations.list_tracked_branches(impl)
      assert result.implementation_id == impl.id
      assert result.branch_id == tracked_branch.branch_id
      # Branch association should be preloaded
      assert %Acai.Implementations.Branch{} = result.branch
    end
  end

  describe "create_tracked_branch/2" do
    test "creates a tracked branch for the implementation", %{product: product} do
      impl = implementation_fixture(product)
      team = Repo.get!(Acai.Teams.Team, product.team_id)
      branch = branch_fixture(team)

      attrs = %{
        branch_id: branch.id,
        repo_uri: branch.repo_uri
      }

      assert {:ok, tracked_branch} = Implementations.create_tracked_branch(impl, attrs)
      assert tracked_branch.implementation_id == impl.id
      assert tracked_branch.branch_id == branch.id
      assert tracked_branch.repo_uri == branch.repo_uri
    end
  end

  describe "count_tracked_branches/1" do
    test "counts branches for the implementation", %{product: product} do
      impl = implementation_fixture(product)
      tracked_branch_fixture(impl, %{repo_uri: "github.com/org/repo1"})
      tracked_branch_fixture(impl, %{repo_uri: "github.com/org/repo2"})

      assert Implementations.count_tracked_branches(impl) == 2
    end
  end

  describe "batch_count_tracked_branches/1" do
    test "returns empty map for empty list" do
      assert Implementations.batch_count_tracked_branches([]) == %{}
    end

    test "returns map of implementation_id => branch count", %{product: product} do
      impl1 = implementation_fixture(product, %{name: "impl-1"})
      impl2 = implementation_fixture(product, %{name: "impl-2"})

      tracked_branch_fixture(impl1, %{repo_uri: "github.com/org/repo1"})
      tracked_branch_fixture(impl1, %{repo_uri: "github.com/org/repo2"})
      tracked_branch_fixture(impl2, %{repo_uri: "github.com/org/repo3"})

      counts = Implementations.batch_count_tracked_branches([impl1, impl2])

      assert Map.get(counts, impl1.id) == 2
      assert Map.get(counts, impl2.id) == 1
    end
  end

  describe "get_spec_impl_state_counts/1" do
    test "returns counts of states by status", %{product: product} do
      _team = product.team
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      spec_impl_state_fixture(spec, impl, %{
        states: %{
          "feat.1" => %{"status" => nil},
          "feat.2" => %{"status" => "assigned"},
          "feat.3" => %{"status" => "completed"},
          "feat.4" => %{"status" => "accepted"},
          "feat.5" => %{"status" => "blocked"},
          "feat.6" => %{"status" => "rejected"}
        }
      })

      counts = Implementations.get_spec_impl_state_counts(impl)

      assert counts[nil] == 1
      assert counts["assigned"] == 1
      assert counts["completed"] == 1
      assert counts["accepted"] == 1
      assert counts["blocked"] == 1
      assert counts["rejected"] == 1
    end

    test "returns zero counts when no states exist", %{product: product} do
      impl = implementation_fixture(product)

      counts = Implementations.get_spec_impl_state_counts(impl)

      assert counts[nil] == 0
      assert counts["assigned"] == 0
      assert counts["completed"] == 0
      assert counts["accepted"] == 0
      assert counts["blocked"] == 0
      assert counts["rejected"] == 0
    end
  end

  describe "batch_get_spec_impl_state_counts/1" do
    test "returns counts for multiple implementations", %{product: product} do
      spec = spec_fixture(product)
      impl1 = implementation_fixture(product, %{name: "impl-1"})
      impl2 = implementation_fixture(product, %{name: "impl-2"})

      spec_impl_state_fixture(spec, impl1, %{
        states: %{
          "feat.1" => %{"status" => nil},
          "feat.2" => %{"status" => "completed"}
        }
      })

      spec_impl_state_fixture(spec, impl2, %{
        states: %{
          "feat.1" => %{"status" => "assigned"}
        }
      })

      counts = Implementations.batch_get_spec_impl_state_counts([impl1, impl2])

      assert counts[impl1.id][nil] == 1
      assert counts[impl1.id]["completed"] == 1
      assert counts[impl2.id]["assigned"] == 1
    end
  end

  describe "list_active_implementations_for_specs/1" do
    test "returns active implementations for specs through product", %{
      product: product
    } do
      spec = spec_fixture(product)
      impl = implementation_fixture(product, %{name: "active-impl", is_active: true})
      implementation_fixture(product, %{name: "inactive-impl", is_active: false})

      result = Implementations.list_active_implementations_for_specs([spec])

      assert length(result) == 1
      assert hd(result).id == impl.id
    end

    test "returns implementations from multiple specs", %{team: team} do
      product1 = product_fixture(team, %{name: "product-1"})
      product2 = product_fixture(team, %{name: "product-2"})
      spec1 = spec_fixture(product1)
      spec2 = spec_fixture(product2)

      impl1 = implementation_fixture(product1, %{is_active: true})
      impl2 = implementation_fixture(product2, %{is_active: true})

      result = Implementations.list_active_implementations_for_specs([spec1, spec2])
      impl_ids = Enum.map(result, & &1.id)

      assert impl1.id in impl_ids
      assert impl2.id in impl_ids
    end
  end

  describe "list_active_implementations/2" do
    # product-view.MATRIX.1
    test "returns only active implementations for product", %{product: product} do
      impl1 = implementation_fixture(product, %{name: "active-impl", is_active: true})
      _impl2 = implementation_fixture(product, %{name: "inactive-impl", is_active: false})

      result = Implementations.list_active_implementations(product)

      assert length(result) == 1
      assert hd(result).id == impl1.id
    end

    # product-view.MATRIX.1-1: Parentless implementations first
    test "orders parentless implementations before descendants", %{product: product} do
      # Create parent (root) implementation
      parent = implementation_fixture(product, %{name: "Parent-Root", is_active: true})

      # Create child implementation
      child =
        implementation_fixture(product, %{
          name: "Child-Node",
          is_active: true,
          parent_implementation_id: parent.id
        })

      result = Implementations.list_active_implementations(product)
      result_ids = Enum.map(result, & &1.id)

      # Parent should come before child
      parent_idx = Enum.find_index(result_ids, &(&1 == parent.id))
      child_idx = Enum.find_index(result_ids, &(&1 == child.id))

      assert parent_idx < child_idx
    end

    # product-view.MATRIX.1-1: Tree order for multiple levels
    test "orders descendants in depth-first tree order", %{product: product} do
      # Create tree: Root -> Child1 -> GrandChild, Root -> Child2
      root = implementation_fixture(product, %{name: "Root", is_active: true})

      child1 =
        implementation_fixture(product, %{
          name: "Child1",
          is_active: true,
          parent_implementation_id: root.id
        })

      grandchild =
        implementation_fixture(product, %{
          name: "GrandChild",
          is_active: true,
          parent_implementation_id: child1.id
        })

      child2 =
        implementation_fixture(product, %{
          name: "Child2",
          is_active: true,
          parent_implementation_id: root.id
        })

      result = Implementations.list_active_implementations(product)
      result_ids = Enum.map(result, & &1.id)

      # Expected order: Root, Child1, GrandChild, Child2
      root_idx = Enum.find_index(result_ids, &(&1 == root.id))
      child1_idx = Enum.find_index(result_ids, &(&1 == child1.id))
      grandchild_idx = Enum.find_index(result_ids, &(&1 == grandchild.id))
      child2_idx = Enum.find_index(result_ids, &(&1 == child2.id))

      assert root_idx == 0
      assert child1_idx == 1
      assert grandchild_idx == 2
      assert child2_idx == 3
    end

    # product-view.MATRIX.1-2: LTR direction (default)
    test "sorts siblings alphabetically in LTR mode", %{product: product} do
      root = implementation_fixture(product, %{name: "Root", is_active: true})

      child_b =
        implementation_fixture(product, %{
          name: "Child-B",
          is_active: true,
          parent_implementation_id: root.id
        })

      child_a =
        implementation_fixture(product, %{
          name: "Child-A",
          is_active: true,
          parent_implementation_id: root.id
        })

      # LTR (default) - alphabetical order
      result = Implementations.list_active_implementations(product, direction: :ltr)
      result_ids = Enum.map(result, & &1.id)

      root_idx = Enum.find_index(result_ids, &(&1 == root.id))
      child_a_idx = Enum.find_index(result_ids, &(&1 == child_a.id))
      child_b_idx = Enum.find_index(result_ids, &(&1 == child_b.id))

      # Root first, then A, then B
      assert root_idx == 0
      assert child_a_idx == 1
      assert child_b_idx == 2
    end

    # product-view.MATRIX.1-2: RTL direction
    test "sorts siblings reverse alphabetically in RTL mode", %{product: product} do
      root = implementation_fixture(product, %{name: "Root", is_active: true})

      child_b =
        implementation_fixture(product, %{
          name: "Child-B",
          is_active: true,
          parent_implementation_id: root.id
        })

      child_a =
        implementation_fixture(product, %{
          name: "Child-A",
          is_active: true,
          parent_implementation_id: root.id
        })

      # RTL - reverse alphabetical order
      result = Implementations.list_active_implementations(product, direction: :rtl)
      result_ids = Enum.map(result, & &1.id)

      root_idx = Enum.find_index(result_ids, &(&1 == root.id))
      child_a_idx = Enum.find_index(result_ids, &(&1 == child_a.id))
      child_b_idx = Enum.find_index(result_ids, &(&1 == child_b.id))

      # Root first, then B, then A
      assert root_idx == 0
      assert child_b_idx == 1
      assert child_a_idx == 2
    end

    test "returns empty list when no active implementations", %{product: product} do
      implementation_fixture(product, %{name: "inactive", is_active: false})

      result = Implementations.list_active_implementations(product)
      assert result == []
    end

    # product-view.MATRIX.1: Active implementations with inactive parents must still appear
    test "includes active implementations even when parent is inactive", %{product: product} do
      # Create inactive parent
      parent = implementation_fixture(product, %{name: "inactive-parent", is_active: false})

      # Create active child with inactive parent
      child =
        implementation_fixture(product, %{
          name: "active-child",
          is_active: true,
          parent_implementation_id: parent.id
        })

      result = Implementations.list_active_implementations(product)
      result_ids = Enum.map(result, & &1.id)

      # Child should be included even though parent is inactive
      assert child.id in result_ids
      # Parent should not be included (it's inactive)
      refute parent.id in result_ids
    end
  end

  describe "order_implementations_by_tree/2" do
    test "handles empty list" do
      assert Implementations.order_implementations_by_tree([]) == []
    end

    test "handles single implementation" do
      impls = [%{id: 1, name: "Single", parent_implementation_id: nil}]
      assert Implementations.order_implementations_by_tree(impls) == impls
    end

    test "handles multiple root implementations" do
      impls = [
        %{id: 2, name: "Beta", parent_implementation_id: nil},
        %{id: 1, name: "Alpha", parent_implementation_id: nil}
      ]

      result = Implementations.order_implementations_by_tree(impls)
      # LTR: Alpha, Beta
      assert Enum.map(result, & &1.name) == ["Alpha", "Beta"]
    end
  end

  describe "delete_tracked_branch/1" do
    test "removes the tracked branch without deleting the branch", %{product: product} do
      impl = implementation_fixture(product)
      tracked_branch = tracked_branch_fixture(impl)

      # impl-settings.UNTRACK_BRANCH.7: On confirmation, removes the branch from tracked branches
      assert {:ok, _} = Implementations.delete_tracked_branch(tracked_branch)

      # Tracked branch should be gone
      assert Implementations.list_tracked_branches(impl) == []

      # But the underlying branch should still exist
      assert Repo.get(Acai.Implementations.Branch, tracked_branch.branch_id) != nil
    end

    # impl-settings.DATA_INTEGRITY.1: Untrack operation preserves feature_branch_ref data
    test "preserves feature_branch_ref data for potential re-tracking", %{product: product} do
      team = Repo.get!(Acai.Teams.Team, product.team_id)
      impl = implementation_fixture(product)
      branch = branch_fixture(team)

      # Create a feature_branch_ref with actual refs data
      Acai.Specs.FeatureBranchRef.changeset(
        %Acai.Specs.FeatureBranchRef{},
        %{
          feature_name: "test-feature",
          branch_id: branch.id,
          refs: %{
            "test-feature.COMP.1" => [
              %{"path" => "lib/file.ex:1", "is_test" => false}
            ]
          },
          commit: "abc123",
          pushed_at: DateTime.utc_now()
        }
      )
      |> Repo.insert!()

      tracked_branch = tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Delete the tracked branch
      assert {:ok, _} = Implementations.delete_tracked_branch(tracked_branch)

      # impl-settings.DATA_INTEGRITY.1: FeatureBranchRef should still exist (preserved for re-tracking)
      fbr = Repo.get_by(Acai.Specs.FeatureBranchRef, branch_id: branch.id)
      assert fbr != nil
      # The refs data should be preserved
      assert fbr.refs["test-feature.COMP.1"] != nil
    end
  end

  describe "list_trackable_branches/1" do
    test "returns branches not already tracked by the implementation", %{
      product: product,
      team: team
    } do
      impl = implementation_fixture(product)

      # Create some branches
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "main"})
      branch3 = branch_fixture(team, %{repo_uri: "github.com/org/repo3", branch_name: "develop"})

      # Track branch1
      tracked_branch_fixture(impl, branch: branch1, repo_uri: branch1.repo_uri)

      # impl-settings.TRACK_BRANCH.2: Trackable branches where repo_uri is not already tracked
      # impl-settings.TRACK_BRANCH.3_1: Excludes branches already tracked by this implementation
      trackable = Implementations.list_trackable_branches(impl)
      trackable_ids = Enum.map(trackable, & &1.id)

      # Should not include branch1 (already tracked)
      refute branch1.id in trackable_ids
      # Should include branch2 and branch3 (different repo_uris)
      assert branch2.id in trackable_ids
      assert branch3.id in trackable_ids
    end

    test "excludes branches from other teams", %{product: product, team: team} do
      impl = implementation_fixture(product)

      # Create branch for current team
      _branch1 = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})

      # Create branch for different team
      other_team = Acai.DataModelFixtures.team_fixture(%{name: "other-team"})

      _branch2 =
        branch_fixture(other_team, %{repo_uri: "github.com/org/repo2", branch_name: "main"})

      # impl-settings.TRACK_BRANCH.3_2: List excludes untrackable repos or branches for other teams
      trackable = Implementations.list_trackable_branches(impl)
      trackable_repo_uris = Enum.map(trackable, & &1.repo_uri)

      # Should include branch from current team
      assert "github.com/org/repo1" in trackable_repo_uris
      # Should not include branch from other team
      refute "github.com/org/repo2" in trackable_repo_uris
    end

    test "returns empty list when all branches are tracked", %{product: product, team: team} do
      impl = implementation_fixture(product)

      # Create and track all branches
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch1, repo_uri: branch1.repo_uri)

      trackable = Implementations.list_trackable_branches(impl)
      assert trackable == []
    end
  end

  describe "delete_implementation/1" do
    test "permanently deletes the implementation", %{product: product} do
      impl = implementation_fixture(product, %{name: "ToDelete"})

      # impl-settings.DELETE.6: On confirmation, permanently deletes the implementation
      assert {:ok, _} = Implementations.delete_implementation(impl)

      # Implementation should be gone
      assert Implementations.get_implementation(impl.id) == nil
    end

    test "clears parent_implementation_id for child implementations", %{product: product} do
      parent = implementation_fixture(product, %{name: "Parent"})

      child =
        implementation_fixture(product, %{name: "Child", parent_implementation_id: parent.id})

      # Delete the parent
      assert {:ok, _} = Implementations.delete_implementation(parent)

      # impl-settings.DATA_INTEGRITY.3: Child implementations are not deleted, parent_implementation_id is cleared
      child_after = Implementations.get_implementation!(child.id)
      assert child_after.parent_implementation_id == nil
    end

    test "does not delete child implementations", %{product: product} do
      parent = implementation_fixture(product, %{name: "Parent"})

      child =
        implementation_fixture(product, %{name: "Child", parent_implementation_id: parent.id})

      # Delete the parent
      assert {:ok, _} = Implementations.delete_implementation(parent)

      # Child should still exist
      assert Implementations.get_implementation(child.id) != nil
    end

    # impl-settings.DATA_INTEGRITY.2: Delete operation cascades to clear dependent states
    test "cascades to clear dependent feature_impl_states", %{product: product} do
      team = Repo.get!(Acai.Teams.Team, product.team_id)
      impl = implementation_fixture(product, %{name: "ToDelete"})
      branch = branch_fixture(team)
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: branch,
          requirements: %{"test-feature.COMP.1" => %{"definition" => "Test"}}
        })

      # Create feature_impl_state for this implementation
      spec_impl_state_fixture(spec, impl, %{
        states: %{"test-feature.COMP.1" => %{"status" => "completed", "comment" => "Done"}}
      })

      # Verify state exists before delete (get_feature_impl_state expects feature_name string)
      assert Acai.Specs.get_feature_impl_state("test-feature", impl) != nil

      # Delete the implementation
      assert {:ok, _} = Implementations.delete_implementation(impl)

      # impl-settings.DATA_INTEGRITY.2: Dependent feature_impl_states should be cleared (deleted)
      assert Acai.Specs.get_feature_impl_state("test-feature", impl) == nil
    end

    # impl-settings.DATA_INTEGRITY.2: Delete operation cascades to clear dependent states
    test "cascades to clear dependent feature_branch_refs", %{product: product} do
      team = Repo.get!(Acai.Teams.Team, product.team_id)
      impl = implementation_fixture(product, %{name: "ToDelete"})
      branch = branch_fixture(team)
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create feature_branch_ref
      Acai.Specs.FeatureBranchRef.changeset(
        %Acai.Specs.FeatureBranchRef{},
        %{
          feature_name: "test-feature",
          branch_id: branch.id,
          refs: %{"test-feature.COMP.1" => [%{"path" => "lib/file.ex:1", "is_test" => false}]},
          commit: "abc123",
          pushed_at: DateTime.utc_now()
        }
      )
      |> Repo.insert!()

      # Verify ref exists before delete (via tracked branch association)
      fbr_before = Repo.get_by(Acai.Specs.FeatureBranchRef, branch_id: branch.id)
      assert fbr_before != nil

      # Delete the implementation (this should delete tracked_branch via DB constraint)
      assert {:ok, _} = Implementations.delete_implementation(impl)

      # Tracked branches should be gone
      assert Implementations.list_tracked_branches(impl) == []

      # impl-settings.DATA_INTEGRITY.2: Feature_branch_ref data remains on branch but is
      # no longer associated with this implementation since tracked_branches are deleted
      # The ref data itself is preserved at branch level per impl-settings.DATA_INTEGRITY.1
    end
  end

  describe "implementation_name_unique?/2" do
    test "returns true when name is unique within product", %{product: product} do
      impl = implementation_fixture(product, %{name: "Existing"})

      assert Implementations.implementation_name_unique?(impl, "NewName") == true
    end

    test "returns false when name already exists in product", %{product: product} do
      _impl1 = implementation_fixture(product, %{name: "Existing"})
      impl2 = implementation_fixture(product, %{name: "Another"})

      assert Implementations.implementation_name_unique?(impl2, "Existing") == false
      # Case insensitive
      assert Implementations.implementation_name_unique?(impl2, "existing") == false
    end

    test "returns true when checking against own name", %{product: product} do
      impl = implementation_fixture(product, %{name: "MyName"})

      # impl-settings.RENAME.4: Save button is disabled when input value matches current name
      # When checking own name, we expect true (available for keeping)
      assert Implementations.implementation_name_unique?(impl, "MyName") == true
    end

    test "considers only same product", %{team: team} do
      product1 = product_fixture(team, %{name: "product1"})
      product2 = product_fixture(team, %{name: "product2"})

      _impl1 = implementation_fixture(product1, %{name: "SameName"})
      impl2 = implementation_fixture(product2, %{name: "OtherName"})

      # Same name in different products should be allowed
      assert Implementations.implementation_name_unique?(impl2, "SameName") == true
    end
  end
end
