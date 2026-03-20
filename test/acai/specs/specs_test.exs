defmodule Acai.SpecsTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs
  alias Acai.Specs.{Spec, FeatureImplState, FeatureBranchRef}

  # Shared setup: team -> product -> spec -> implementation
  defp setup_spec_chain(_ctx \\ %{}) do
    team = team_fixture()
    product = product_fixture(team)
    spec = spec_fixture(product)
    impl = implementation_fixture(product)
    %{team: team, product: product, spec: spec, impl: impl}
  end

  describe "list_specs/2" do
    test "returns empty list when no specs exist" do
      team = team_fixture()
      current_scope = %{user: %{id: 1}}
      assert Specs.list_specs(current_scope, team) == []
    end

    test "returns specs for the team" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      current_scope = %{user: %{id: 1}}

      assert [^spec] = Specs.list_specs(current_scope, team)
    end

    test "does not return specs from other teams" do
      team1 = team_fixture()
      team2 = team_fixture()
      product1 = product_fixture(team1)
      product_fixture(team2)
      spec_fixture(product1)
      current_scope = %{user: %{id: 1}}

      assert Specs.list_specs(current_scope, team2) == []
    end
  end

  describe "list_specs_for_product/1" do
    test "returns specs for the product" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)

      assert [^spec] = Specs.list_specs_for_product(product)
    end

    test "does not return specs from other products" do
      team = team_fixture()
      product1 = product_fixture(team, %{name: "product-1"})
      product2 = product_fixture(team, %{name: "product-2"})
      spec_fixture(product1)

      assert Specs.list_specs_for_product(product2) == []
    end
  end

  describe "get_spec!/1" do
    test "returns the spec by id" do
      %{spec: spec} = setup_spec_chain()
      assert Specs.get_spec!(spec.id).id == spec.id
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Specs.get_spec!(Acai.UUIDv7.autogenerate())
      end
    end
  end

  describe "create_spec/4" do
    test "creates a spec linked to the product" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()
      current_scope = %{user: %{id: 1}}

      attrs = %{
        branch_id: branch.id,
        last_seen_commit: "abc123",
        parsed_at: DateTime.utc_now(),
        feature_name: "new-feature"
      }

      assert {:ok, %Spec{} = spec} = Specs.create_spec(current_scope, team, product, attrs)
      assert spec.feature_name == "new-feature"
      assert spec.product_id == product.id
      assert spec.branch_id == branch.id
    end

    test "returns error changeset when attrs are invalid" do
      team = team_fixture()
      product = product_fixture(team)
      current_scope = %{user: %{id: 1}}

      assert {:error, changeset} = Specs.create_spec(current_scope, team, product, %{})
      refute changeset.valid?
    end
  end

  describe "update_spec/2" do
    test "updates the spec" do
      %{spec: spec} = setup_spec_chain()
      attrs = %{feature_description: "Updated description", feature_version: "2.0.0"}

      assert {:ok, %Spec{} = updated} = Specs.update_spec(spec, attrs)
      assert updated.feature_description == "Updated description"
      assert updated.feature_version == "2.0.0"
    end

    test "returns error changeset when attrs are invalid" do
      %{spec: spec} = setup_spec_chain()
      assert {:error, changeset} = Specs.update_spec(spec, %{feature_name: ""})
      refute changeset.valid?
    end
  end

  describe "change_spec/2" do
    test "returns a changeset for the spec" do
      %{spec: spec} = setup_spec_chain()
      cs = Specs.change_spec(spec, %{feature_name: "new-name"})
      assert cs.changes == %{feature_name: "new-name"}
    end

    test "returns a blank changeset with no attrs" do
      %{spec: spec} = setup_spec_chain()
      cs = Specs.change_spec(spec)
      assert cs.changes == %{}
    end
  end

  describe "list_specs_grouped_by_product/1" do
    test "returns empty map when no specs exist" do
      team = team_fixture()
      assert Specs.list_specs_grouped_by_product(team) == %{}
    end

    test "returns specs grouped by product name" do
      team = team_fixture()
      product1 = product_fixture(team, %{name: "product-a"})
      product2 = product_fixture(team, %{name: "product-b"})
      spec1 = spec_fixture(product1, %{feature_name: "feature-1"})
      spec2 = spec_fixture(product1, %{feature_name: "feature-2"})
      spec3 = spec_fixture(product2, %{feature_name: "feature-3"})

      grouped = Specs.list_specs_grouped_by_product(team)

      assert length(Map.get(grouped, "product-a", [])) == 2
      assert length(Map.get(grouped, "product-b", [])) == 1
      # Compare by ID since the product association is preloaded in grouped specs
      grouped_ids = Enum.map(grouped["product-a"], & &1.id)
      assert spec1.id in grouped_ids
      assert spec2.id in grouped_ids
      assert spec3.id in Enum.map(grouped["product-b"], & &1.id)
    end

    test "does not include specs from other teams" do
      team1 = team_fixture()
      team2 = team_fixture()
      product = product_fixture(team1, %{name: "shared-name"})
      spec_fixture(product)

      assert Specs.list_specs_grouped_by_product(team2) == %{}
    end
  end

  describe "get_spec_by_feature_name/2" do
    test "returns the spec by feature_name for the team" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product, %{feature_name: "my-feature"})

      assert Specs.get_spec_by_feature_name(team, "my-feature").id == spec.id
    end

    test "returns nil when no spec found" do
      team = team_fixture()
      assert Specs.get_spec_by_feature_name(team, "nonexistent") == nil
    end

    test "does not return specs from other teams" do
      team1 = team_fixture()
      team2 = team_fixture()
      product = product_fixture(team1)
      spec_fixture(product, %{feature_name: "my-feature"})

      assert Specs.get_spec_by_feature_name(team2, "my-feature") == nil
    end
  end

  describe "get_specs_by_feature_name/2" do
    test "returns specs and actual feature_name for the team" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product, %{feature_name: "my-feature"})

      assert {"my-feature", [^spec]} = Specs.get_specs_by_feature_name(team, "my-feature")
    end

    test "is case-insensitive" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product, %{feature_name: "My-Feature"})

      assert {"My-Feature", [^spec]} = Specs.get_specs_by_feature_name(team, "my-feature")
    end

    test "returns nil when no spec found" do
      team = team_fixture()
      assert Specs.get_specs_by_feature_name(team, "nonexistent") == nil
    end
  end

  describe "get_specs_by_product_name/2" do
    test "returns specs and actual product name for the team" do
      team = team_fixture()
      product = product_fixture(team, %{name: "my-product"})
      spec = spec_fixture(product)

      assert {"my-product", [^spec]} = Specs.get_specs_by_product_name(team, "my-product")
    end

    test "is case-insensitive" do
      team = team_fixture()
      product = product_fixture(team, %{name: "My-Product"})
      spec_fixture(product)

      assert {"My-Product", [_]} = Specs.get_specs_by_product_name(team, "my-product")
    end

    test "returns nil when no product found" do
      team = team_fixture()
      assert Specs.get_specs_by_product_name(team, "nonexistent") == nil
    end
  end

  # --- FeatureImplState tests ---

  describe "get_feature_impl_state/2" do
    test "returns the state for feature_name and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      state = spec_impl_state_fixture(spec, impl)

      assert Specs.get_feature_impl_state(spec.feature_name, impl).id == state.id
    end

    test "returns nil when no state exists" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      assert Specs.get_feature_impl_state(spec.feature_name, impl) == nil
    end
  end

  describe "create_feature_impl_state/3" do
    test "creates a state for feature_name and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      attrs = %{
        states: %{
          "test.COMP.1" => %{"status" => "pending", "comment" => "Test"}
        }
      }

      assert {:ok, %FeatureImplState{} = state} =
               Specs.create_feature_impl_state(spec.feature_name, impl, attrs)

      assert state.feature_name == spec.feature_name
      assert state.implementation_id == impl.id
      assert state.states["test.COMP.1"]["status"] == "pending"
    end

    test "returns error changeset when attrs are invalid" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      assert {:error, changeset} =
               Specs.create_feature_impl_state(spec.feature_name, impl, %{states: nil})

      refute changeset.valid?
    end
  end

  describe "update_feature_impl_state/2" do
    test "updates the state" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      state = spec_impl_state_fixture(spec, impl)

      new_states = %{
        "test.COMP.1" => %{"status" => "completed", "comment" => "Done"}
      }

      assert {:ok, %FeatureImplState{} = updated} =
               Specs.update_feature_impl_state(state, %{states: new_states})

      assert updated.states["test.COMP.1"]["status"] == "completed"
    end
  end

  describe "upsert_feature_impl_state/3" do
    test "inserts a new state when none exists" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      attrs = %{
        states: %{
          "test.COMP.1" => %{"status" => "in_progress"}
        }
      }

      assert {:ok, %FeatureImplState{} = state} =
               Specs.upsert_feature_impl_state(spec.feature_name, impl, attrs)

      assert state.feature_name == spec.feature_name
      assert state.implementation_id == impl.id
    end

    test "updates existing state on conflict" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      {:ok, original} =
        Specs.upsert_feature_impl_state(spec.feature_name, impl, %{
          states: %{"a" => %{"status" => "pending"}}
        })

      {:ok, updated} =
        Specs.upsert_feature_impl_state(spec.feature_name, impl, %{
          states: %{"a" => %{"status" => "completed"}}
        })

      assert updated.id == original.id
      assert updated.states["a"]["status"] == "completed"
    end
  end

  describe "apply_feature_impl_status_change/4" do
    # feature-impl-view.LIST.3-2: Deep-merge / apply-status helper tests
    test "creates new state row when none exists" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      assert {:ok, %FeatureImplState{} = state} =
               Specs.apply_feature_impl_status_change(
                 spec.feature_name,
                 impl,
                 "test.COMP.1",
                 "completed"
               )

      assert state.feature_name == spec.feature_name
      assert state.implementation_id == impl.id
      assert state.states["test.COMP.1"]["status"] == "completed"
      assert state.states["test.COMP.1"]["updated_at"] != nil
    end

    test "preserves sibling ACIDs when updating one ACID" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      # Create initial state with multiple ACIDs
      {:ok, _} =
        Specs.create_feature_impl_state(spec.feature_name, impl, %{
          states: %{
            "test.COMP.1" => %{"status" => "completed", "comment" => "First done"},
            "test.COMP.2" => %{"status" => "assigned", "comment" => "Second in progress"},
            "test.COMP.3" => %{"status" => "accepted", "comment" => "Third accepted"}
          }
        })

      # Update only COMP.2
      assert {:ok, %FeatureImplState{} = state} =
               Specs.apply_feature_impl_status_change(
                 spec.feature_name,
                 impl,
                 "test.COMP.2",
                 "blocked"
               )

      # All three ACIDs should still exist
      assert map_size(state.states) == 3

      # COMP.2 should be updated
      assert state.states["test.COMP.2"]["status"] == "blocked"
      # Comment should be preserved
      assert state.states["test.COMP.2"]["comment"] == "Second in progress"
      # updated_at should be set
      assert state.states["test.COMP.2"]["updated_at"] != nil

      # COMP.1 and COMP.3 should be unchanged
      assert state.states["test.COMP.1"]["status"] == "completed"
      assert state.states["test.COMP.1"]["comment"] == "First done"
      assert state.states["test.COMP.3"]["status"] == "accepted"
      assert state.states["test.COMP.3"]["comment"] == "Third accepted"
    end

    test "preserves existing comment and metadata when updating status" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      # Create initial state with comment and metadata
      {:ok, _} =
        Specs.create_feature_impl_state(spec.feature_name, impl, %{
          states: %{
            "test.COMP.1" => %{
              "status" => "assigned",
              "comment" => "This is a comment",
              "metadata" => %{"priority" => "high", "assignee" => "alice"}
            }
          }
        })

      # Update status
      assert {:ok, %FeatureImplState{} = state} =
               Specs.apply_feature_impl_status_change(
                 spec.feature_name,
                 impl,
                 "test.COMP.1",
                 "completed"
               )

      # Status should be updated
      assert state.states["test.COMP.1"]["status"] == "completed"
      # Comment should be preserved
      assert state.states["test.COMP.1"]["comment"] == "This is a comment"
      # Metadata should be preserved
      assert state.states["test.COMP.1"]["metadata"]["priority"] == "high"
      assert state.states["test.COMP.1"]["metadata"]["assignee"] == "alice"
      # updated_at should be set
      assert state.states["test.COMP.1"]["updated_at"] != nil
    end

    test "sets updated_at when status actually changes" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      old_timestamp = "2024-01-01T00:00:00Z"

      {:ok, _} =
        Specs.create_feature_impl_state(spec.feature_name, impl, %{
          states: %{
            "test.COMP.1" => %{"status" => "assigned", "updated_at" => old_timestamp}
          }
        })

      assert {:ok, %FeatureImplState{} = state} =
               Specs.apply_feature_impl_status_change(
                 spec.feature_name,
                 impl,
                 "test.COMP.1",
                 "completed"
               )

      # updated_at should be updated to a new value
      assert state.states["test.COMP.1"]["updated_at"] != old_timestamp
    end

    test "works correctly when parent has inherited states but child has no local row" do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent implementation with states
      parent_impl = implementation_fixture(product, %{name: "Parent"})
      _parent_spec = spec_fixture(product, %{feature_name: "inheritance-test"})

      {:ok, _} =
        Specs.create_feature_impl_state("inheritance-test", parent_impl, %{
          states: %{
            "inheritance-test.COMP.1" => %{"status" => "completed", "comment" => "Parent done"},
            "inheritance-test.COMP.2" => %{
              "status" => "assigned",
              "comment" => "Parent in progress"
            }
          }
        })

      # Create child implementation with no local states
      child_impl =
        implementation_fixture(product, %{
          name: "Child",
          parent_implementation_id: parent_impl.id
        })

      # Child changes COMP.2 to blocked
      assert {:ok, %FeatureImplState{} = child_state} =
               Specs.apply_feature_impl_status_change(
                 "inheritance-test",
                 child_impl,
                 "inheritance-test.COMP.2",
                 "blocked"
               )

      # Child's local state should ONLY contain COMP.2
      assert map_size(child_state.states) == 1
      assert child_state.states["inheritance-test.COMP.2"]["status"] == "blocked"
      # Comment from parent should NOT be copied (child started fresh)
      assert child_state.states["inheritance-test.COMP.2"]["comment"] == nil

      # Parent's state should be unchanged
      parent_state = Specs.get_feature_impl_state("inheritance-test", parent_impl)
      assert parent_state.states["inheritance-test.COMP.1"]["status"] == "completed"
      assert parent_state.states["inheritance-test.COMP.2"]["status"] == "assigned"
    end
  end

  # --- FeatureBranchRef tests (branch-scoped refs) ---

  describe "get_feature_branch_ref/2" do
    test "returns the ref for feature_name and branch" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      # Create tracked branch and feature_branch_ref
      tracked_branch = tracked_branch_fixture(impl)
      branch = Acai.Repo.preload(tracked_branch, :branch).branch
      ref_record = feature_branch_ref_fixture(branch, spec.feature_name)

      assert Specs.get_feature_branch_ref(spec.feature_name, branch).id ==
               ref_record.id
    end

    test "returns nil when no ref exists" do
      team = team_fixture()
      branch = branch_fixture(team)

      assert Specs.get_feature_branch_ref("nonexistent", branch) == nil
    end
  end

  describe "create_feature_branch_ref/3" do
    test "creates a ref for feature_name and branch" do
      team = team_fixture()
      branch = branch_fixture(team)

      attrs = %{
        refs: %{
          "test.COMP.1" => [
            %{"path" => "lib/foo.ex:42", "is_test" => false}
          ]
        },
        commit: "abc123",
        pushed_at: DateTime.utc_now()
      }

      assert {:ok, %FeatureBranchRef{} = ref_record} =
               Specs.create_feature_branch_ref("test-feature", branch, attrs)

      assert ref_record.feature_name == "test-feature"
      assert ref_record.branch_id == branch.id
    end

    test "returns error changeset when attrs are invalid" do
      team = team_fixture()
      branch = branch_fixture(team)

      assert {:error, changeset} =
               Specs.create_feature_branch_ref("test-feature", branch, %{refs: nil})

      refute changeset.valid?
    end
  end

  describe "update_feature_branch_ref/2" do
    test "updates the ref" do
      team = team_fixture()
      branch = branch_fixture(team)

      {:ok, ref_record} =
        Specs.create_feature_branch_ref("test-feature", branch, %{
          refs: %{"a" => [%{"path" => "lib/foo.ex:1", "is_test" => false}]},
          commit: "abc123",
          pushed_at: DateTime.utc_now()
        })

      new_refs = %{
        "test.COMP.1" => [%{"path" => "lib/bar.ex:2", "is_test" => true}]
      }

      assert {:ok, %FeatureBranchRef{} = updated} =
               Specs.update_feature_branch_ref(ref_record, %{refs: new_refs})

      assert updated.refs["test.COMP.1"] |> hd() |> Map.get("path") == "lib/bar.ex:2"
    end
  end

  describe "upsert_feature_branch_ref/3" do
    test "inserts a new ref when none exists" do
      team = team_fixture()
      branch = branch_fixture(team)

      attrs = %{
        refs: %{"a" => [%{"path" => "lib/foo.ex:1", "is_test" => false}]},
        commit: "def456",
        pushed_at: DateTime.utc_now()
      }

      assert {:ok, %FeatureBranchRef{} = ref_record} =
               Specs.upsert_feature_branch_ref("test-feature", branch, attrs)

      assert ref_record.feature_name == "test-feature"
      assert ref_record.branch_id == branch.id
    end

    test "updates existing ref on conflict" do
      team = team_fixture()
      branch = branch_fixture(team)

      {:ok, original} =
        Specs.upsert_feature_branch_ref("test-feature", branch, %{
          refs: %{"a" => [%{"path" => "lib/foo.ex:1", "is_test" => false}]},
          commit: "abc",
          pushed_at: DateTime.utc_now()
        })

      {:ok, updated} =
        Specs.upsert_feature_branch_ref("test-feature", branch, %{
          refs: %{"a" => [%{"path" => "lib/bar.ex:2", "is_test" => true}]},
          commit: "def",
          pushed_at: DateTime.utc_now()
        })

      assert updated.id == original.id
      assert updated.refs["a"] |> hd() |> Map.get("path") == "lib/bar.ex:2"
    end
  end

  # --- Legacy API tests (backwards compatibility) ---

  describe "get_spec_impl_state/2 (legacy)" do
    test "returns the state for spec and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      state = spec_impl_state_fixture(spec, impl)

      assert Specs.get_spec_impl_state(spec, impl).id == state.id
    end

    test "returns nil when no state exists" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      assert Specs.get_spec_impl_state(spec, impl) == nil
    end
  end

  describe "create_spec_impl_state/3 (legacy)" do
    test "creates a state for spec and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      attrs = %{
        states: %{
          "test.COMP.1" => %{"status" => "pending", "comment" => "Test"}
        }
      }

      assert {:ok, %FeatureImplState{} = state} = Specs.create_spec_impl_state(spec, impl, attrs)
      assert state.feature_name == spec.feature_name
      assert state.implementation_id == impl.id
      assert state.states["test.COMP.1"]["status"] == "pending"
    end
  end

  describe "upsert_spec_impl_state/3 (legacy)" do
    test "inserts a new state when none exists" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      attrs = %{
        states: %{
          "test.COMP.1" => %{"status" => "in_progress"}
        }
      }

      assert {:ok, %FeatureImplState{} = state} = Specs.upsert_spec_impl_state(spec, impl, attrs)
      assert state.feature_name == spec.feature_name
      assert state.implementation_id == impl.id
    end
  end

  describe "get_spec_impl_ref/2 (legacy)" do
    test "returns ref counts for spec and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      # Create tracked branch and ref
      tracked_branch = tracked_branch_fixture(impl)
      branch = Acai.Repo.preload(tracked_branch, :branch).branch
      _ref_record = feature_branch_ref_fixture(branch, spec.feature_name)

      result = Specs.get_spec_impl_ref(spec, impl)
      # Now returns a pseudo-ref structure with counts
      assert result.total_refs >= 0
      assert result.total_tests >= 0
    end
  end

  describe "create_spec_impl_ref/3 (legacy)" do
    test "creates refs on tracked branches for spec and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      # Need a tracked branch first
      _tracked_branch = tracked_branch_fixture(impl)

      attrs = %{
        refs: %{
          "test.COMP.1" => [
            %{"path" => "lib/foo.ex:10", "is_test" => false}
          ]
        },
        commit: "abc123",
        pushed_at: DateTime.utc_now()
      }

      # Legacy function now returns {:ok, %{}}
      assert {:ok, _} = Specs.create_spec_impl_ref(spec, impl, attrs)
    end
  end

  describe "upsert_spec_impl_ref/3 (legacy)" do
    test "upserts refs on tracked branches for spec and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      # Need a tracked branch first
      _tracked_branch = tracked_branch_fixture(impl)

      attrs = %{
        refs: %{"a" => [%{"path" => "lib/foo.ex:1", "is_test" => false}]},
        commit: "def456",
        pushed_at: DateTime.utc_now()
      }

      # Legacy function now returns {:ok, %{}}
      assert {:ok, _} = Specs.upsert_spec_impl_ref(spec, impl, attrs)
    end
  end

  # --- Canonical Spec Resolution with Inheritance ---

  describe "resolve_canonical_spec/2" do
    test "returns spec on implementation's tracked branch as local", %{} do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      # Create tracked branch
      tracked_branch =
        tracked_branch_fixture(impl, repo_uri: "github.com/org/repo", branch_name: "main")

      branch = Acai.Repo.preload(tracked_branch, :branch).branch

      # Create spec on the tracked branch - use branch: branch to pass the branch struct
      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: branch,
          repo_uri: "github.com/org/repo"
        })

      assert {resolved_spec, source_info} = Specs.resolve_canonical_spec("test-feature", impl.id)
      assert resolved_spec.id == spec.id
      assert source_info.is_inherited == false
      assert source_info.source_implementation_id == nil
      assert source_info.source_branch.id == branch.id
    end

    # feature-impl-view.INHERITANCE.1
    test "returns spec from parent when not on tracked branches", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent implementation with tracked branch and spec
      parent_impl = implementation_fixture(product, %{name: "parent"})

      parent_tracked =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: parent_branch,
          repo_uri: "github.com/org/repo"
        })

      # Create child implementation without tracked branch
      child_impl =
        implementation_fixture(product, %{
          name: "child",
          parent_implementation_id: parent_impl.id
        })

      assert {resolved_spec, source_info} =
               Specs.resolve_canonical_spec("test-feature", child_impl.id)

      assert resolved_spec.id == spec.id
      assert source_info.is_inherited == true
      assert source_info.source_implementation_id == parent_impl.id
    end

    # feature-impl-view.ROUTING.4: feature_name scoped to implementation tracked branches
    test "returns nil when no spec on tracked branches or parent chain", %{} do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)
      # No tracked branches, no parent, no spec

      assert {nil, nil} = Specs.resolve_canonical_spec("nonexistent-feature", impl.id)
    end

    test "walks multiple levels of parent chain", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create grandparent with spec
      grandparent = implementation_fixture(product, %{name: "grandparent"})

      grandparent_tracked =
        tracked_branch_fixture(grandparent, repo_uri: "github.com/org/repo", branch_name: "main")

      grandparent_branch = Acai.Repo.preload(grandparent_tracked, :branch).branch

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: grandparent_branch,
          repo_uri: "github.com/org/repo"
        })

      # Create parent without spec
      parent =
        implementation_fixture(product, %{
          name: "parent",
          parent_implementation_id: grandparent.id
        })

      # Create child without spec
      child =
        implementation_fixture(product, %{
          name: "child",
          parent_implementation_id: parent.id
        })

      assert {resolved_spec, source_info} = Specs.resolve_canonical_spec("test-feature", child.id)
      assert resolved_spec.id == spec.id
      assert source_info.is_inherited == true
      assert source_info.source_implementation_id == grandparent.id
    end

    test "prevents infinite loops with circular references", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create two implementations that reference each other
      impl1 = implementation_fixture(product, %{name: "impl1"})

      impl2 =
        implementation_fixture(product, %{
          name: "impl2",
          parent_implementation_id: impl1.id
        })

      # Create circular reference
      Acai.Repo.update!(Ecto.Changeset.change(impl1, parent_implementation_id: impl2.id))

      # Should not hang, should return nil
      assert {nil, nil} = Specs.resolve_canonical_spec("test-feature", impl1.id)
    end

    # feature-impl-view.ROUTING.4: Same-name specs on untracked branches are ignored
    test "ignores same-name spec on untracked branch", %{} do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      # Create a branch but don't track it for this implementation
      untracked_branch =
        branch_fixture(team, %{
          repo_uri: "github.com/org/untracked",
          branch_name: "untracked-branch"
        })

      # Create spec on the untracked branch
      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: untracked_branch,
        repo_uri: "github.com/org/untracked",
        requirements: %{
          "test-feature.COMP.1" => %{
            "definition" => "Untracked req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Should not find the spec since it's not on a tracked branch
      assert {nil, nil} = Specs.resolve_canonical_spec("test-feature", impl.id)
    end

    # feature-impl-view.ROUTING.4: feature_name matching scoped to tracked branches only
    test "only considers specs on implementation's tracked branches", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create two implementations
      impl_with_spec = implementation_fixture(product, %{name: "with-spec"})
      impl_without_spec = implementation_fixture(product, %{name: "without-spec"})

      # Create tracked branch only for impl_with_spec
      tracked =
        tracked_branch_fixture(impl_with_spec,
          repo_uri: "github.com/org/repo",
          branch_name: "main"
        )

      tracked_branch = Acai.Repo.preload(tracked, :branch).branch

      # Create spec on the tracked branch
      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: tracked_branch,
          repo_uri: "github.com/org/repo",
          requirements: %{
            "test-feature.COMP.1" => %{
              "definition" => "Tracked req",
              "is_deprecated" => false,
              "replaced_by" => []
            }
          }
        })

      # impl_with_spec should find the spec
      assert {resolved_spec, source_info} =
               Specs.resolve_canonical_spec("test-feature", impl_with_spec.id)

      assert resolved_spec.id == spec.id
      assert source_info.is_inherited == false

      # impl_without_spec should not find the spec (different tracked branches)
      assert {nil, nil} = Specs.resolve_canonical_spec("test-feature", impl_without_spec.id)
    end

    # feature-impl-view.ROUTING.4: Same-name specs on untracked branches are ignored
    test "ignores spec on untracked branch even if product matches", %{} do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      # Create a branch but don't track it for this implementation
      untracked_branch =
        branch_fixture(team, %{
          repo_uri: "github.com/org/untracked",
          branch_name: "untracked-branch"
        })

      # Create spec on the untracked branch for the product
      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: untracked_branch,
        repo_uri: "github.com/org/untracked",
        requirements: %{
          "test-feature.COMP.1" => %{
            "definition" => "Untracked req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Should not find the spec since it's not on a tracked branch
      assert {nil, nil} = Specs.resolve_canonical_spec("test-feature", impl.id)
    end

    # feature-impl-view.ROUTING.4: spec must belong to the same product as the implementation
    test "does not resolve spec from another product on shared tracked branch", %{} do
      team = team_fixture()
      product_a = product_fixture(team, %{name: "product-a"})
      product_b = product_fixture(team, %{name: "product-b"})

      # Create implementations for different products
      impl_a = implementation_fixture(product_a, %{name: "impl-a"})
      impl_b = implementation_fixture(product_b, %{name: "impl-b"})

      # Create a shared branch that both implementations track
      shared_branch =
        branch_fixture(team, %{
          repo_uri: "github.com/org/shared",
          branch_name: "main"
        })

      # Both implementations track the same branch
      tracked_branch_fixture(impl_a, branch: shared_branch, repo_uri: shared_branch.repo_uri)
      tracked_branch_fixture(impl_b, branch: shared_branch, repo_uri: shared_branch.repo_uri)

      # Create a spec for product_a on the shared branch
      spec_fixture(product_a, %{
        feature_name: "shared-feature",
        branch: shared_branch,
        repo_uri: "github.com/org/shared",
        requirements: %{
          "shared-feature.COMP.1" => %{
            "definition" => "Product A req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # impl_a should find the spec (same product)
      assert {resolved_spec, source_info} =
               Specs.resolve_canonical_spec("shared-feature", impl_a.id)

      assert resolved_spec.product_id == product_a.id
      assert source_info.is_inherited == false

      # impl_b should NOT find the spec (different product, despite tracking same branch)
      assert {nil, nil} = Specs.resolve_canonical_spec("shared-feature", impl_b.id)
    end

    # feature-impl-view.ROUTING.4: inherited specs must also match product
    test "does not inherit spec from parent if parent has different product", %{} do
      team = team_fixture()
      product_a = product_fixture(team, %{name: "product-a"})
      product_b = product_fixture(team, %{name: "product-b"})

      # Create parent implementation in product_a with tracked branch and spec
      parent_impl = implementation_fixture(product_a, %{name: "parent"})

      parent_tracked =
        tracked_branch_fixture(parent_impl,
          repo_uri: "github.com/org/repo",
          branch_name: "main"
        )

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      spec_fixture(product_a, %{
        feature_name: "inherited-feature",
        branch: parent_branch,
        repo_uri: "github.com/org/repo",
        requirements: %{
          "inherited-feature.COMP.1" => %{
            "definition" => "Product A req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create child implementation in product_b with parent in product_a
      # This is an edge case that shouldn't normally happen, but we should handle it
      child_impl =
        implementation_fixture(product_b, %{
          name: "child",
          parent_implementation_id: parent_impl.id
        })

      # Child should NOT inherit the spec because it's from a different product
      assert {nil, nil} = Specs.resolve_canonical_spec("inherited-feature", child_impl.id)
    end
  end

  describe "list_features_for_implementation/2" do
    test "returns features from specs on tracked branches for the product", %{} do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      # Create tracked branch with spec
      tracked = tracked_branch_fixture(impl, repo_uri: "github.com/org/repo", branch_name: "main")
      branch = Acai.Repo.preload(tracked, :branch).branch

      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: branch,
        repo_uri: "github.com/org/repo"
      })

      features = Specs.list_features_for_implementation(impl, product)
      assert {"test-feature", "test-feature"} in features
    end

    # feature-impl-view.INHERITANCE.1
    test "includes features inherited from parent implementation", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent with spec on tracked branch
      parent = implementation_fixture(product, %{name: "parent"})

      parent_tracked =
        tracked_branch_fixture(parent, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      spec_fixture(product, %{
        feature_name: "inherited-feature",
        branch: parent_branch,
        repo_uri: "github.com/org/repo"
      })

      # Create child without tracked branches
      child =
        implementation_fixture(product, %{name: "child", parent_implementation_id: parent.id})

      # Child should see inherited feature
      features = Specs.list_features_for_implementation(child, product)
      assert {"inherited-feature", "inherited-feature"} in features
    end

    # feature-impl-view.ROUTING.4
    test "excludes features from other products on shared branch", %{} do
      team = team_fixture()
      product_a = product_fixture(team, %{name: "product-a"})
      product_b = product_fixture(team, %{name: "product-b"})

      impl_a = implementation_fixture(product_a)

      # Create shared branch
      shared_branch =
        branch_fixture(team, %{repo_uri: "github.com/org/shared", branch_name: "main"})

      tracked_branch_fixture(impl_a, branch: shared_branch, repo_uri: shared_branch.repo_uri)

      # Create specs for different products on same branch
      spec_fixture(product_a, %{
        feature_name: "feature-a",
        branch: shared_branch,
        repo_uri: "github.com/org/shared"
      })

      spec_fixture(product_b, %{
        feature_name: "feature-b",
        branch: shared_branch,
        repo_uri: "github.com/org/shared"
      })

      # Product A's implementation should only see feature-a
      features = Specs.list_features_for_implementation(impl_a, product_a)
      assert {"feature-a", "feature-a"} in features
      refute {"feature-b", "feature-b"} in features
    end

    test "returns empty list when no specs accessible", %{} do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      # No tracked branches, no specs
      assert Specs.list_features_for_implementation(impl, product) == []
    end

    test "returns empty list when specs are for different product", %{} do
      team = team_fixture()
      product_a = product_fixture(team, %{name: "product-a"})
      product_b = product_fixture(team, %{name: "product-b"})
      impl_a = implementation_fixture(product_a)

      # Create spec for product_b
      branch = branch_fixture(team)
      tracked_branch_fixture(impl_a, branch: branch, repo_uri: branch.repo_uri)

      spec_fixture(product_b, %{
        feature_name: "other-product-feature",
        branch: branch,
        repo_uri: branch.repo_uri
      })

      # impl_a (product_a) should not see product_b's feature
      assert Specs.list_features_for_implementation(impl_a, product_a) == []
    end
  end

  describe "list_implementations_for_feature/2" do
    test "returns implementations with spec on tracked branch", %{} do
      team = team_fixture()
      product = product_fixture(team)

      impl_with_spec = implementation_fixture(product, %{name: "with-spec"})
      _impl_without_spec = implementation_fixture(product, %{name: "without-spec"})

      # Create tracked branch and spec for one implementation
      tracked =
        tracked_branch_fixture(impl_with_spec,
          repo_uri: "github.com/org/repo",
          branch_name: "main"
        )

      branch = Acai.Repo.preload(tracked, :branch).branch

      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: branch,
        repo_uri: "github.com/org/repo"
      })

      implementations = Specs.list_implementations_for_feature("test-feature", product)
      impl_names = Enum.map(implementations, & &1.name)

      assert "with-spec" in impl_names
      refute "without-spec" in impl_names
    end

    # feature-impl-view.INHERITANCE.1
    test "includes implementations that inherit feature from parent", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent with spec
      parent = implementation_fixture(product, %{name: "parent"})

      parent_tracked =
        tracked_branch_fixture(parent, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      spec_fixture(product, %{
        feature_name: "inherited-feature",
        branch: parent_branch,
        repo_uri: "github.com/org/repo"
      })

      # Create child that inherits
      _child =
        implementation_fixture(product, %{name: "child", parent_implementation_id: parent.id})

      implementations = Specs.list_implementations_for_feature("inherited-feature", product)
      impl_names = Enum.map(implementations, & &1.name)

      assert "parent" in impl_names
      assert "child" in impl_names
    end

    test "excludes implementations from other products", %{} do
      team = team_fixture()
      product_a = product_fixture(team, %{name: "product-a"})
      product_b = product_fixture(team, %{name: "product-b"})

      impl_a = implementation_fixture(product_a, %{name: "impl-a"})
      _impl_b = implementation_fixture(product_b, %{name: "impl-b"})

      # Create spec for product_a
      branch = branch_fixture(team)
      tracked_branch_fixture(impl_a, branch: branch, repo_uri: branch.repo_uri)

      spec_fixture(product_a, %{
        feature_name: "test-feature",
        branch: branch,
        repo_uri: branch.repo_uri
      })

      # Query for product_a - should only see impl_a
      implementations = Specs.list_implementations_for_feature("test-feature", product_a)
      impl_names = Enum.map(implementations, & &1.name)

      assert "impl-a" in impl_names
      refute "impl-b" in impl_names
    end

    test "returns empty list when no implementations have the feature", %{} do
      team = team_fixture()
      product = product_fixture(team)
      _impl = implementation_fixture(product)

      assert Specs.list_implementations_for_feature("nonexistent-feature", product) == []
    end

    # feature-impl-view.ROUTING.4: list_implementations_for_feature/2 should exclude cross-product specs
    test "excludes implementation when matching spec is from another product", %{} do
      team = team_fixture()
      product_a = product_fixture(team, %{name: "product-a"})
      product_b = product_fixture(team, %{name: "product-b"})

      # Create implementations for each product
      impl_a = implementation_fixture(product_a, %{name: "impl-a"})
      impl_b = implementation_fixture(product_b, %{name: "impl-b"})

      # Create a shared branch that both implementations track
      shared_branch =
        branch_fixture(team, %{
          repo_uri: "github.com/org/shared",
          branch_name: "main"
        })

      # Both implementations track the same branch
      tracked_branch_fixture(impl_a, branch: shared_branch, repo_uri: shared_branch.repo_uri)
      tracked_branch_fixture(impl_b, branch: shared_branch, repo_uri: shared_branch.repo_uri)

      # Create a spec for product_a on the shared branch
      spec_fixture(product_a, %{
        feature_name: "shared-feature",
        branch: shared_branch,
        repo_uri: "github.com/org/shared",
        requirements: %{
          "shared-feature.COMP.1" => %{
            "definition" => "Product A req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Query for product_a - should include impl_a
      implementations_a = Specs.list_implementations_for_feature("shared-feature", product_a)
      impl_names_a = Enum.map(implementations_a, & &1.name)

      assert "impl-a" in impl_names_a

      # Query for product_b - should NOT include impl_b (no matching spec for product_b)
      implementations_b = Specs.list_implementations_for_feature("shared-feature", product_b)
      impl_names_b = Enum.map(implementations_b, & &1.name)

      refute "impl-b" in impl_names_b
    end
  end

  describe "resolve_canonical_spec/2 continued" do
    # feature-impl-view.INHERITANCE.1: Nearest ancestor resolution
    test "prefers nearest ancestor over distant ancestor", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create grandparent with spec
      grandparent = implementation_fixture(product, %{name: "grandparent"})

      grandparent_tracked =
        tracked_branch_fixture(grandparent, repo_uri: "github.com/org/repo", branch_name: "main")

      grandparent_branch = Acai.Repo.preload(grandparent_tracked, :branch).branch

      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: grandparent_branch,
        repo_uri: "github.com/org/repo",
        requirements: %{
          "test-feature.COMP.1" => %{
            "definition" => "Grandparent req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create parent with its own spec
      parent =
        implementation_fixture(product, %{
          name: "parent",
          parent_implementation_id: grandparent.id
        })

      parent_tracked =
        tracked_branch_fixture(parent, repo_uri: "github.com/org/repo2", branch_name: "develop")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      parent_spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: parent_branch,
          repo_uri: "github.com/org/repo2",
          requirements: %{
            "test-feature.COMP.1" => %{
              "definition" => "Parent req",
              "is_deprecated" => false,
              "replaced_by" => []
            }
          }
        })

      # Create child without spec
      child =
        implementation_fixture(product, %{name: "child", parent_implementation_id: parent.id})

      # Should find parent's spec (nearest ancestor), not grandparent's
      assert {resolved_spec, source_info} = Specs.resolve_canonical_spec("test-feature", child.id)
      assert resolved_spec.id == parent_spec.id
      assert source_info.is_inherited == true
      assert source_info.source_implementation_id == parent.id
    end
  end

  describe "batch_get_spec_impl_completion/2 inheritance" do
    # product-view.MATRIX.3-1: Child with no local row inherits parent completion
    test "child with no local row inherits parent completion", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent with spec
      parent = implementation_fixture(product, %{name: "parent"})

      parent_tracked =
        tracked_branch_fixture(parent, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      parent_spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: parent_branch,
          repo_uri: "github.com/org/repo",
          requirements: %{
            "test-feature.COMP.1" => %{"definition" => "Req 1"},
            "test-feature.COMP.2" => %{"definition" => "Req 2"}
          }
        })

      # Create child without spec (inherits from parent)
      child =
        implementation_fixture(product, %{name: "child", parent_implementation_id: parent.id})

      # Create feature_impl_state for parent only (2 requirements, 1 completed)
      Acai.Specs.create_feature_impl_state("test-feature", parent, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "assigned"}
        }
      })

      # Child has no local feature_impl_state row

      # Call batch_get_spec_impl_completion
      result = Specs.batch_get_spec_impl_completion([parent_spec], [parent, child])

      # Parent should have 1/2 completed (50%)
      assert result[{parent_spec.id, parent.id}] == %{completed: 1, total: 2}

      # Child should inherit from parent: 1/2 completed (50%)
      assert result[{parent_spec.id, child.id}] == %{completed: 1, total: 2}
    end

    # product-view.MATRIX.3-1: Multi-level ancestry inherits recursively from grandparent
    test "multi-level ancestry inherits recursively from grandparent when needed", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create grandparent with spec
      grandparent = implementation_fixture(product, %{name: "grandparent"})

      grandparent_tracked =
        tracked_branch_fixture(grandparent, repo_uri: "github.com/org/repo", branch_name: "main")

      grandparent_branch = Acai.Repo.preload(grandparent_tracked, :branch).branch

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: grandparent_branch,
          repo_uri: "github.com/org/repo",
          requirements: %{
            "test-feature.COMP.1" => %{"definition" => "Req 1"},
            "test-feature.COMP.2" => %{"definition" => "Req 2"},
            "test-feature.COMP.3" => %{"definition" => "Req 3"}
          }
        })

      # Create parent with no local state (will inherit from grandparent)
      parent =
        implementation_fixture(product, %{
          name: "parent",
          parent_implementation_id: grandparent.id
        })

      # Create grandchild with no local state (will inherit from grandparent via parent)
      grandchild =
        implementation_fixture(product, %{
          name: "grandchild",
          parent_implementation_id: parent.id
        })

      # Create feature_impl_state for grandparent only (3 requirements, 2 completed)
      Acai.Specs.create_feature_impl_state("test-feature", grandparent, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "completed"},
          "test-feature.COMP.3" => %{"status" => "assigned"}
        }
      })

      # Call batch_get_spec_impl_completion
      result = Specs.batch_get_spec_impl_completion([spec], [grandparent, parent, grandchild])

      # All should inherit from grandparent: 2/3 completed
      assert result[{spec.id, grandparent.id}] == %{completed: 2, total: 3}
      assert result[{spec.id, parent.id}] == %{completed: 2, total: 3}
      assert result[{spec.id, grandchild.id}] == %{completed: 2, total: 3}
    end

    # product-view.MATRIX.3-1: Local child row overrides inherited progress
    test "local child row overrides inherited progress", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent with spec
      parent = implementation_fixture(product, %{name: "parent"})

      parent_tracked =
        tracked_branch_fixture(parent, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: parent_branch,
          repo_uri: "github.com/org/repo",
          requirements: %{
            "test-feature.COMP.1" => %{"definition" => "Req 1"},
            "test-feature.COMP.2" => %{"definition" => "Req 2"}
          }
        })

      # Create child with parent
      child =
        implementation_fixture(product, %{name: "child", parent_implementation_id: parent.id})

      # Create feature_impl_state for parent (2 requirements, 1 completed = 50%)
      Acai.Specs.create_feature_impl_state("test-feature", parent, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "assigned"}
        }
      })

      # Create feature_impl_state for child (2 requirements, 2 completed = 100%)
      Acai.Specs.create_feature_impl_state("test-feature", child, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "completed"}
        }
      })

      # Call batch_get_spec_impl_completion
      result = Specs.batch_get_spec_impl_completion([spec], [parent, child])

      # Parent should have 1/2 completed (50%)
      assert result[{spec.id, parent.id}] == %{completed: 1, total: 2}

      # Child should use its own local row: 2/2 completed (100%)
      assert result[{spec.id, child.id}] == %{completed: 2, total: 2}
    end

    # product-view.MATRIX.3-1: Local empty row stays 0% and does not inherit
    test "local empty %{} row stays 0% and does not inherit", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent with spec
      parent = implementation_fixture(product, %{name: "parent"})

      parent_tracked =
        tracked_branch_fixture(parent, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: parent_branch,
          repo_uri: "github.com/org/repo",
          requirements: %{
            "test-feature.COMP.1" => %{"definition" => "Req 1"},
            "test-feature.COMP.2" => %{"definition" => "Req 2"}
          }
        })

      # Create child with parent
      child =
        implementation_fixture(product, %{name: "child", parent_implementation_id: parent.id})

      # Create feature_impl_state for parent (2 requirements, 2 completed = 100%)
      Acai.Specs.create_feature_impl_state("test-feature", parent, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "completed"}
        }
      })

      # Create feature_impl_state for child with EMPTY states map (not nil, but empty)
      # This represents a local row that exists but has no state data
      Acai.Specs.create_feature_impl_state("test-feature", child, %{
        states: %{}
      })

      # Call batch_get_spec_impl_completion
      result = Specs.batch_get_spec_impl_completion([spec], [parent, child])

      # Parent should have 2/2 completed (100%)
      assert result[{spec.id, parent.id}] == %{completed: 2, total: 2}

      # Child should use its empty local row: 0/2 completed (0%)
      # NOT inherit from parent
      assert result[{spec.id, child.id}] == %{completed: 0, total: 2}
    end

    # product-view.MATRIX.3-1: Nearest ancestor with row is used
    test "inherits from nearest ancestor that has a row", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create grandparent with spec
      grandparent = implementation_fixture(product, %{name: "grandparent"})

      grandparent_tracked =
        tracked_branch_fixture(grandparent, repo_uri: "github.com/org/repo", branch_name: "main")

      grandparent_branch = Acai.Repo.preload(grandparent_tracked, :branch).branch

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: grandparent_branch,
          repo_uri: "github.com/org/repo",
          requirements: %{
            "test-feature.COMP.1" => %{"definition" => "Req 1"},
            "test-feature.COMP.2" => %{"definition" => "Req 2"}
          }
        })

      # Create parent with row (1/2 completed)
      parent =
        implementation_fixture(product, %{
          name: "parent",
          parent_implementation_id: grandparent.id
        })

      # Create child with no row (should inherit from parent, not grandparent)
      child =
        implementation_fixture(product, %{
          name: "child",
          parent_implementation_id: parent.id
        })

      # Create feature_impl_state for grandparent (2/2 completed = 100%)
      Acai.Specs.create_feature_impl_state("test-feature", grandparent, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "completed"}
        }
      })

      # Create feature_impl_state for parent (1/2 completed = 50%)
      Acai.Specs.create_feature_impl_state("test-feature", parent, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "assigned"}
        }
      })

      # Child has no local row

      # Call batch_get_spec_impl_completion
      result = Specs.batch_get_spec_impl_completion([spec], [grandparent, parent, child])

      # Grandparent: 2/2 (100%)
      assert result[{spec.id, grandparent.id}] == %{completed: 2, total: 2}

      # Parent: 1/2 (50%)
      assert result[{spec.id, parent.id}] == %{completed: 1, total: 2}

      # Child should inherit from nearest ancestor (parent): 1/2 (50%)
      assert result[{spec.id, child.id}] == %{completed: 1, total: 2}
    end

    # product-view.ROUTING.2: Returns empty map for empty inputs
    test "returns empty map when specs is empty", %{} do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      result = Specs.batch_get_spec_impl_completion([], [impl])
      assert result == %{}
    end

    # product-view.ROUTING.2: Returns empty map for empty implementations
    test "returns empty map when implementations is empty", %{} do
      team = team_fixture()
      product = product_fixture(team)

      branch = branch_fixture(team)

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: branch,
          repo_uri: branch.repo_uri,
          requirements: %{
            "test-feature.COMP.1" => %{"definition" => "Req 1"}
          }
        })

      result = Specs.batch_get_spec_impl_completion([spec], [])
      assert result == %{}
    end
  end

  # --- Feature Page Consolidated Loader Tests ---

  describe "load_feature_page_data/2" do
    # feature-view.ENG.1: Single query fetches all specs, implementations, and state counts
    test "returns all feature page data in single call", %{} do
      team = team_fixture()
      product = product_fixture(team, %{name: "test-product"})

      # Create tracked branch and spec
      branch = branch_fixture(team)

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          feature_description: "Test feature description",
          branch: branch,
          repo_uri: branch.repo_uri,
          requirements: %{
            "test-feature.COMP.1" => %{
              "definition" => "Req 1",
              "is_deprecated" => false,
              "replaced_by" => []
            },
            "test-feature.COMP.2" => %{
              "definition" => "Req 2",
              "is_deprecated" => false,
              "replaced_by" => []
            }
          }
        })

      # Create implementation with tracked branch
      impl =
        implementation_fixture(product, %{
          name: "test-impl",
          is_active: true
        })

      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create feature impl state
      Acai.Specs.create_feature_impl_state("test-feature", impl, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "assigned"}
        }
      })

      # Load all feature page data
      assert {:ok, data} = Specs.load_feature_page_data(team, "test-feature")

      # Verify all data is present
      assert data.feature_name == "test-feature"
      assert data.feature_description == "Test feature description"
      assert data.product.id == product.id
      assert length(data.specs) == 1
      assert hd(data.specs).id == spec.id
      assert data.total_requirements == 2
      assert length(data.implementations) == 1
      assert hd(data.implementations).id == impl.id

      # Verify available features for dropdown
      assert {"test-feature", "test-feature"} in data.available_features

      # Verify status counts
      impl_counts = Map.get(data.status_counts_by_impl, impl.id, %{})
      assert impl_counts["completed"] == 1
      assert impl_counts["assigned"] == 1
    end

    # feature-view.ENG.1: Returns error when feature not found
    test "returns error when feature not found", %{} do
      team = team_fixture()

      assert {:error, :feature_not_found} = Specs.load_feature_page_data(team, "nonexistent")
    end

    # feature-view.MAIN.2: Only active implementations that can resolve the feature
    test "only includes active implementations with the feature", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create tracked branch and spec
      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{
          "test-feature.COMP.1" => %{"definition" => "Req 1"}
        }
      })

      # Create active implementation with tracked branch (has feature)
      active_with_feature =
        implementation_fixture(product, %{
          name: "active-with-feature",
          is_active: true
        })

      tracked_branch_fixture(active_with_feature, branch: branch, repo_uri: branch.repo_uri)

      # Create active implementation without tracked branch (no feature)
      _active_no_feature =
        implementation_fixture(product, %{
          name: "active-no-feature",
          is_active: true
        })

      # Create inactive implementation with tracked branch (has feature but inactive)
      inactive_with_feature =
        implementation_fixture(product, %{
          name: "inactive-with-feature",
          is_active: false
        })

      tracked_branch_fixture(inactive_with_feature, branch: branch, repo_uri: branch.repo_uri)

      # Load feature page data
      assert {:ok, data} = Specs.load_feature_page_data(team, "test-feature")

      # Should only include the active implementation with the feature
      impl_names = Enum.map(data.implementations, & &1.name)
      assert "active-with-feature" in impl_names
      refute "active-no-feature" in impl_names
      refute "inactive-with-feature" in impl_names
    end

    # feature-view.ENG.2: Respects inheritance semantics
    test "includes implementations that inherit the feature from parent", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent with spec
      parent =
        implementation_fixture(product, %{
          name: "parent",
          is_active: true
        })

      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{
          "test-feature.COMP.1" => %{"definition" => "Req 1"}
        }
      })

      tracked_branch_fixture(parent, branch: branch, repo_uri: branch.repo_uri)

      # Create child that inherits (no tracked branch, has parent)
      _child =
        implementation_fixture(product, %{
          name: "child",
          is_active: true,
          parent_implementation_id: parent.id
        })

      # Load feature page data
      assert {:ok, data} = Specs.load_feature_page_data(team, "test-feature")

      # Should include both parent and child
      impl_names = Enum.map(data.implementations, & &1.name)
      assert "parent" in impl_names
      assert "child" in impl_names
    end

    # feature-view.ENG.2: Inherited state counts for child implementations
    test "includes inherited state counts for child implementations", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent with spec
      parent =
        implementation_fixture(product, %{
          name: "parent",
          is_active: true
        })

      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{
          "test-feature.COMP.1" => %{"definition" => "Req 1"},
          "test-feature.COMP.2" => %{"definition" => "Req 2"}
        }
      })

      tracked_branch_fixture(parent, branch: branch, repo_uri: branch.repo_uri)

      # Create child that inherits
      child =
        implementation_fixture(product, %{
          name: "child",
          is_active: true,
          parent_implementation_id: parent.id
        })

      # Create state for parent only (child should inherit)
      Acai.Specs.create_feature_impl_state("test-feature", parent, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "assigned"}
        }
      })

      # Load feature page data
      assert {:ok, data} = Specs.load_feature_page_data(team, "test-feature")

      # Parent should have its own state
      parent_counts = Map.get(data.status_counts_by_impl, parent.id, %{})

      assert parent_counts["completed"] == 1
      assert parent_counts["assigned"] == 1

      # Child should inherit parent's state
      child_counts = Map.get(data.status_counts_by_impl, child.id, %{})

      assert child_counts["completed"] == 1
      assert child_counts["assigned"] == 1
    end

    # feature-impl-view.ROUTING.4: Same-product scoping for shared branches
    test "excludes specs from other products on shared branch", %{} do
      team = team_fixture()
      product_a = product_fixture(team, %{name: "product-a"})
      product_b = product_fixture(team, %{name: "product-b"})

      # Create shared branch
      shared_branch =
        branch_fixture(team, %{
          repo_uri: "github.com/org/shared",
          branch_name: "main"
        })

      # Create implementations for each product tracking the same branch
      impl_a =
        implementation_fixture(product_a, %{
          name: "impl-a",
          is_active: true
        })

      impl_b =
        implementation_fixture(product_b, %{
          name: "impl-b",
          is_active: true
        })

      tracked_branch_fixture(impl_a, branch: shared_branch, repo_uri: shared_branch.repo_uri)
      tracked_branch_fixture(impl_b, branch: shared_branch, repo_uri: shared_branch.repo_uri)

      # Create spec for product_a only on the shared branch
      spec_fixture(product_a, %{
        feature_name: "shared-feature",
        branch: shared_branch,
        repo_uri: "github.com/org/shared",
        requirements: %{
          "shared-feature.COMP.1" => %{
            "definition" => "Product A req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Load feature page data for product_a
      assert {:ok, data} = Specs.load_feature_page_data(team, "shared-feature")

      # Should include impl_a (same product as spec)
      impl_names = Enum.map(data.implementations, & &1.name)
      assert "impl-a" in impl_names

      # Should NOT include impl_b (different product, no matching spec)
      refute "impl-b" in impl_names
    end
  end

  describe "list_implementations_for_feature_batched/2" do
    # feature-view.ENG.1: Batched query approach
    test "returns only active implementations with the feature", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create tracked branch and spec
      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{
          "test-feature.COMP.1" => %{"definition" => "Req 1"}
        }
      })

      # Create implementations
      active_with =
        implementation_fixture(product, %{
          name: "active-with",
          is_active: true
        })

      _active_without =
        implementation_fixture(product, %{
          name: "active-without",
          is_active: true
        })

      inactive_with =
        implementation_fixture(product, %{
          name: "inactive-with",
          is_active: false
        })

      tracked_branch_fixture(active_with, branch: branch, repo_uri: branch.repo_uri)
      tracked_branch_fixture(inactive_with, branch: branch, repo_uri: branch.repo_uri)

      # Get implementations using batched loader
      implementations =
        Specs.list_implementations_for_feature_batched("test-feature", product)

      impl_names = Enum.map(implementations, & &1.name)
      assert "active-with" in impl_names
      refute "active-without" in impl_names
      refute "inactive-with" in impl_names
    end

    # feature-view.ENG.2: Respects inheritance
    test "includes implementations that inherit the feature", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent with spec
      parent =
        implementation_fixture(product, %{
          name: "parent",
          is_active: true
        })

      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{
          "test-feature.COMP.1" => %{"definition" => "Req 1"}
        }
      })

      tracked_branch_fixture(parent, branch: branch, repo_uri: branch.repo_uri)

      # Create child that inherits
      _child =
        implementation_fixture(product, %{
          name: "child",
          is_active: true,
          parent_implementation_id: parent.id
        })

      # Get implementations
      implementations =
        Specs.list_implementations_for_feature_batched("test-feature", product)

      impl_names = Enum.map(implementations, & &1.name)
      assert "parent" in impl_names
      assert "child" in impl_names
    end

    # feature-view.MAIN.5: Empty state
    test "returns empty list when no implementations have the feature", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create implementation without the feature
      _impl =
        implementation_fixture(product, %{
          name: "no-feature",
          is_active: true
        })

      # Get implementations
      implementations =
        Specs.list_implementations_for_feature_batched("nonexistent-feature", product)

      assert implementations == []
    end
  end

  describe "batch_check_feature_availability/2" do
    # product-view.MATRIX.7-1
    test "returns true when feature is available on tracked branch", %{} do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      # Create tracked branch with spec
      tracked = tracked_branch_fixture(impl, repo_uri: "github.com/org/repo", branch_name: "main")
      branch = Acai.Repo.preload(tracked, :branch).branch

      spec_fixture(product, %{
        feature_name: "available-feature",
        branch: branch,
        repo_uri: "github.com/org/repo"
      })

      result = Specs.batch_check_feature_availability(["available-feature"], [impl])

      assert result[{"available-feature", impl.id}] == true
    end

    # product-view.MATRIX.7-1
    test "returns true when feature is inherited from parent", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent with spec
      parent = implementation_fixture(product, %{name: "parent"})

      parent_tracked =
        tracked_branch_fixture(parent, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      spec_fixture(product, %{
        feature_name: "inherited-feature",
        branch: parent_branch,
        repo_uri: "github.com/org/repo"
      })

      # Create child without tracked branch
      child =
        implementation_fixture(product, %{
          name: "child",
          parent_implementation_id: parent.id
        })

      result = Specs.batch_check_feature_availability(["inherited-feature"], [child])

      assert result[{"inherited-feature", child.id}] == true
    end

    # product-view.MATRIX.8
    test "returns false when feature is not available for implementation", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create implementation without any tracked branches
      impl = implementation_fixture(product)

      # Create a spec but on a different branch that's not tracked
      other_branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "unavailable-feature",
        branch: other_branch,
        repo_uri: "github.com/org/other"
      })

      result = Specs.batch_check_feature_availability(["unavailable-feature"], [impl])

      assert result[{"unavailable-feature", impl.id}] == false
    end

    # product-view.MATRIX.8
    test "returns false when feature not found anywhere in ancestor chain", %{} do
      team = team_fixture()
      product = product_fixture(team)

      # Create parent without any spec
      parent = implementation_fixture(product, %{name: "parent"})

      # Create child
      child =
        implementation_fixture(product, %{
          name: "child",
          parent_implementation_id: parent.id
        })

      result = Specs.batch_check_feature_availability(["nonexistent-feature"], [child])

      assert result[{"nonexistent-feature", child.id}] == false
    end

    test "handles multiple features and implementations", %{} do
      team = team_fixture()
      product = product_fixture(team)

      impl1 = implementation_fixture(product, %{name: "impl1"})
      impl2 = implementation_fixture(product, %{name: "impl2"})

      # Track a branch for impl1 only
      tracked =
        tracked_branch_fixture(impl1, repo_uri: "github.com/org/repo", branch_name: "main")

      branch = Acai.Repo.preload(tracked, :branch).branch

      spec_fixture(product, %{
        feature_name: "feature-a",
        branch: branch,
        repo_uri: "github.com/org/repo"
      })

      result =
        Specs.batch_check_feature_availability(["feature-a", "feature-b"], [impl1, impl2])

      # impl1 has feature-a
      assert result[{"feature-a", impl1.id}] == true
      # impl1 doesn't have feature-b
      assert result[{"feature-b", impl1.id}] == false
      # impl2 doesn't have anything (no tracked branches)
      assert result[{"feature-a", impl2.id}] == false
      assert result[{"feature-b", impl2.id}] == false
    end

    test "returns empty map for empty inputs" do
      assert Specs.batch_check_feature_availability([], []) == %{}
      assert Specs.batch_check_feature_availability(["feature"], []) == %{}
      assert Specs.batch_check_feature_availability([], [%{id: 1}]) == %{}
    end

    # product-view.MATRIX.8: Unavailable cells stay unavailable when same-name spec
    # exists only on a shared tracked branch for another product
    test "returns false when matching spec belongs to a different product on shared branch",
         %{} do
      team = team_fixture()
      product_a = product_fixture(team, %{name: "product-a"})
      product_b = product_fixture(team, %{name: "product-b"})

      # Create implementations for each product
      impl_a = implementation_fixture(product_a, %{name: "impl-a"})
      impl_b = implementation_fixture(product_b, %{name: "impl-b"})

      # Create a shared branch that both implementations track
      shared_branch =
        branch_fixture(team, %{
          repo_uri: "github.com/org/shared",
          branch_name: "main"
        })

      # Both implementations track the same branch
      tracked_branch_fixture(impl_a, branch: shared_branch, repo_uri: shared_branch.repo_uri)
      tracked_branch_fixture(impl_b, branch: shared_branch, repo_uri: shared_branch.repo_uri)

      # Create a spec for product_a on the shared branch
      spec_fixture(product_a, %{
        feature_name: "shared-feature",
        branch: shared_branch,
        repo_uri: "github.com/org/shared",
        requirements: %{
          "shared-feature.COMP.1" => %{
            "definition" => "Product A req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # batch_check_feature_availability should only see specs for the same product
      # When checking impl_a (product_a), the feature should be available
      result_a = Specs.batch_check_feature_availability(["shared-feature"], [impl_a])
      assert result_a[{"shared-feature", impl_a.id}] == true

      # When checking impl_b (product_b), the feature should NOT be available
      # because the spec is for product_a, not product_b
      result_b = Specs.batch_check_feature_availability(["shared-feature"], [impl_b])
      assert result_b[{"shared-feature", impl_b.id}] == false
    end

    # product-view.MATRIX.7-1: Inheritance respects product boundaries
    test "returns false when inherited spec would come from different product", %{} do
      team = team_fixture()
      product_a = product_fixture(team, %{name: "product-a"})
      product_b = product_fixture(team, %{name: "product-b"})

      # Create parent in product_a with tracked branch and spec
      parent_impl = implementation_fixture(product_a, %{name: "parent"})

      parent_tracked =
        tracked_branch_fixture(parent_impl,
          repo_uri: "github.com/org/repo",
          branch_name: "main"
        )

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      spec_fixture(product_a, %{
        feature_name: "inherited-feature",
        branch: parent_branch,
        repo_uri: "github.com/org/repo",
        requirements: %{
          "inherited-feature.COMP.1" => %{
            "definition" => "Product A req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create child in product_b with parent in product_a
      child_impl =
        implementation_fixture(product_b, %{
          name: "child",
          parent_implementation_id: parent_impl.id
        })

      # Child should NOT see the feature as available because
      # the inherited spec is from a different product
      result = Specs.batch_check_feature_availability(["inherited-feature"], [child_impl])
      assert result[{"inherited-feature", child_impl.id}] == false
    end
  end

  # ============================================================================
  # Feature Settings - Deletion Helpers
  # ============================================================================

  describe "delete_feature_impl_state/2" do
    # feature-settings.CLEAR_STATES.5: On confirmation, all feature_impl_states for this feature are deleted
    test "deletes the local feature_impl_state for the feature and implementation" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product, %{feature_name: "test-feature"})
      impl = implementation_fixture(product)

      # Create a feature_impl_state
      state =
        spec_impl_state_fixture(spec, impl, %{
          states: %{"test-feature.COMP.1" => %{"status" => "accepted"}}
        })

      # Verify it exists
      assert Specs.get_feature_impl_state("test-feature", impl).id == state.id

      # Delete it
      assert {:ok, _} = Specs.delete_feature_impl_state("test-feature", impl)

      # Verify it's deleted
      assert is_nil(Specs.get_feature_impl_state("test-feature", impl))
    end

    test "returns ok when no state exists" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      # Try to delete non-existent state
      assert {:ok, nil} = Specs.delete_feature_impl_state("nonexistent-feature", impl)
    end
  end

  describe "local_feature_impl_state_exists?/2" do
    # feature-settings.CLEAR_STATES.2_1: Button is disabled when no feature_impl_states exist for this feature and implementation
    test "returns true when a local feature_impl_state exists" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product, %{feature_name: "test-feature"})
      impl = implementation_fixture(product)

      spec_impl_state_fixture(spec, impl, %{states: %{}})

      assert Specs.local_feature_impl_state_exists?("test-feature", impl) == true
    end

    test "returns false when no local feature_impl_state exists" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      assert Specs.local_feature_impl_state_exists?("nonexistent-feature", impl) == false
    end
  end

  describe "delete_feature_branch_refs_for_branches/2" do
    # feature-settings.CLEAR_REFS.6: On confirmation, feature_branch_refs are cleared for all selected branches
    test "deletes feature_branch_refs for the given branch IDs and feature_name" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)
      branch = branch_fixture(team)

      # Track the branch
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create a feature_branch_ref
      spec_impl_ref_fixture(
        spec_fixture(product, %{feature_name: "test-feature", branch: branch}),
        impl,
        %{refs: %{"test-feature.COMP.1" => [%{"path" => "lib/test.ex:1", "is_test" => false}]}}
      )

      # Verify it exists
      assert Specs.local_feature_branch_refs_exist?([branch.id], "test-feature") == true

      # Delete it
      assert {:ok, 1} = Specs.delete_feature_branch_refs_for_branches([branch.id], "test-feature")

      # Verify it's deleted
      assert Specs.local_feature_branch_refs_exist?([branch.id], "test-feature") == false
    end

    test "returns 0 count when no refs exist" do
      team = team_fixture()
      branch = branch_fixture(team)

      assert {:ok, 0} =
               Specs.delete_feature_branch_refs_for_branches([branch.id], "nonexistent-feature")
    end

    test "deletes refs for multiple branches" do
      team = team_fixture()

      # Create two different branches with different repo_uris
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "main"})

      # Create refs directly using the feature_branch_ref_fixture
      feature_branch_ref_fixture(branch1, "test-feature", %{refs: %{}, commit: "abc123"})
      feature_branch_ref_fixture(branch2, "test-feature", %{refs: %{}, commit: "def456"})

      # Verify both exist
      assert Specs.local_feature_branch_refs_exist?([branch1.id], "test-feature") == true
      assert Specs.local_feature_branch_refs_exist?([branch2.id], "test-feature") == true

      # Delete refs for both branches
      assert {:ok, 2} =
               Specs.delete_feature_branch_refs_for_branches(
                 [branch1.id, branch2.id],
                 "test-feature"
               )

      # Verify both are deleted
      assert Specs.local_feature_branch_refs_exist?([branch1.id, branch2.id], "test-feature") ==
               false
    end
  end

  describe "local_feature_branch_refs_exist?/2" do
    # feature-settings.CLEAR_REFS.2_1: Button is disabled when no feature_branch_refs exist for any tracked branch
    test "returns true when refs exist for the given branch IDs" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)
      branch = branch_fixture(team)

      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      spec_impl_ref_fixture(
        spec_fixture(product, %{feature_name: "test-feature", branch: branch}),
        impl,
        %{refs: %{}}
      )

      assert Specs.local_feature_branch_refs_exist?([branch.id], "test-feature") == true
    end

    test "returns false when no refs exist" do
      team = team_fixture()
      branch = branch_fixture(team)

      assert Specs.local_feature_branch_refs_exist?([branch.id], "nonexistent-feature") == false
    end

    test "returns false for empty branch IDs list" do
      assert Specs.local_feature_branch_refs_exist?([], "test-feature") == false
    end
  end

  describe "delete_spec/1" do
    # feature-settings.DELETE_SPEC.5: On confirmation, the target spec for the current tracked branch is deleted
    test "deletes the spec" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)

      assert {:ok, _} = Specs.delete_spec(spec)

      assert_raise Ecto.NoResultsError, fn ->
        Specs.get_spec!(spec.id)
      end
    end
  end
end
