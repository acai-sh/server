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
end
