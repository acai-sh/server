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

  # --- Spec Inheritance Tests ---

  describe "get_spec_for_feature_with_inheritance/2" do
    setup do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      child_impl =
        implementation_fixture(product, %{
          name: "child-impl",
          parent_implementation_id: parent_impl.id
        })

      # Create spec on parent's tracked branch
      parent_tracked_branch = tracked_branch_fixture(parent_impl, %{branch: branch})

      spec_on_parent =
        spec_fixture(product, %{
          branch: branch,
          feature_name: "inherited-feature"
        })

      %{
        team: team,
        product: product,
        branch: branch,
        parent_impl: parent_impl,
        child_impl: child_impl,
        spec_on_parent: spec_on_parent,
        parent_tracked_branch: parent_tracked_branch
      }
    end

    test "returns spec found directly on impl's tracked branch", ctx do
      # Create a child-specific spec (different version to avoid unique constraint)
      child_branch = branch_fixture()
      tracked_branch_fixture(ctx.child_impl, %{branch: child_branch})

      child_spec =
        spec_fixture(ctx.product, %{
          branch: child_branch,
          feature_name: "inherited-feature",
          feature_version: "2.0.0"
        })

      # data-model.INHERITANCE.3: Child spec takes precedence
      assert {spec, source_impl_id} =
               Specs.get_spec_for_feature_with_inheritance("inherited-feature", ctx.child_impl.id)

      assert spec.id == child_spec.id
      assert source_impl_id == ctx.child_impl.id
    end

    test "returns spec from parent's tracked branch when not on child", ctx do
      # data-model.INHERITANCE.2, data-model.INHERITANCE.4
      assert {spec, source_impl_id} =
               Specs.get_spec_for_feature_with_inheritance("inherited-feature", ctx.child_impl.id)

      assert spec.id == ctx.spec_on_parent.id
      assert source_impl_id == ctx.parent_impl.id
    end

    test "returns spec from grandparent when not on parent or child", ctx do
      # Create grandchild
      grandchild_impl =
        implementation_fixture(ctx.product, %{
          name: "grandchild-impl",
          parent_implementation_id: ctx.child_impl.id
        })

      # data-model.INHERITANCE.5: Recurses up the chain
      assert {spec, source_impl_id} =
               Specs.get_spec_for_feature_with_inheritance(
                 "inherited-feature",
                 grandchild_impl.id
               )

      assert spec.id == ctx.spec_on_parent.id
      assert source_impl_id == ctx.parent_impl.id
    end

    test "returns {nil, nil} when spec not found anywhere in chain", ctx do
      # data-model.INHERITANCE.1: Chain via parent_implementation_id
      assert {nil, nil} =
               Specs.get_spec_for_feature_with_inheritance(
                 "nonexistent-feature",
                 ctx.child_impl.id
               )
    end

    test "child spec takes precedence over parent spec", ctx do
      # Create child-specific spec with same feature name (different version)
      child_branch = branch_fixture()
      tracked_branch_fixture(ctx.child_impl, %{branch: child_branch})

      child_spec =
        spec_fixture(ctx.product, %{
          branch: child_branch,
          feature_name: "inherited-feature",
          feature_version: "2.0.0"
        })

      # data-model.INHERITANCE.3: Child's spec takes precedence
      assert {spec, source_impl_id} =
               Specs.get_spec_for_feature_with_inheritance("inherited-feature", ctx.child_impl.id)

      assert spec.id == child_spec.id
      assert source_impl_id == ctx.child_impl.id
    end

    test "circular parent reference doesn't infinite loop", ctx do
      # Create a circular reference: parent -> child (instead of child -> parent)
      # First, update parent to point to child
      {:ok, _} =
        Acai.Implementations.update_implementation(ctx.parent_impl, %{
          parent_implementation_id: ctx.child_impl.id
        })

      # This should not hang - it uses visited set to prevent loops
      assert {_spec, _source_impl_id} =
               Specs.get_spec_for_feature_with_inheritance(
                 "inherited-feature",
                 ctx.parent_impl.id
               )
    end

    test "returns {nil, nil} for implementation with no tracked branches and no parent", ctx do
      orphan_impl = implementation_fixture(ctx.product, %{name: "orphan-impl"})

      assert {nil, nil} =
               Specs.get_spec_for_feature_with_inheritance("any-feature", orphan_impl.id)
    end
  end

  describe "get_inheritance_summary/2" do
    setup do
      team = team_fixture()
      product = product_fixture(team)

      parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      child_impl =
        implementation_fixture(product, %{
          name: "child-impl",
          parent_implementation_id: parent_impl.id
        })

      parent_branch = branch_fixture()
      tracked_branch_fixture(parent_impl, %{branch: parent_branch})

      parent_spec = spec_fixture(product, %{branch: parent_branch, feature_name: "test-feature"})

      %{
        team: team,
        product: product,
        parent_impl: parent_impl,
        child_impl: child_impl,
        parent_spec: parent_spec
      }
    end

    test "returns all inherited when nothing exists on child", ctx do
      # Create states and refs on parent
      spec_impl_state_fixture(ctx.parent_spec, ctx.parent_impl, %{
        states: %{"test.COMP.1" => %{"status" => "completed"}}
      })

      spec_impl_ref_fixture(ctx.parent_spec, ctx.parent_impl, %{
        refs: %{"test.COMP.1" => [%{"path" => "lib/foo.ex"}]}
      })

      summary = Specs.get_inheritance_summary("test-feature", ctx.child_impl.id)

      # feature-impl-view.INHERITANCE.1, feature-impl-view.INHERITANCE.3
      assert summary.spec.inherited? == true
      assert summary.spec.found? == true
      assert summary.spec.source_impl_id == ctx.parent_impl.id

      assert summary.states.inherited? == true
      assert summary.states.found? == true
      assert summary.states.source_impl_id == ctx.parent_impl.id

      assert summary.refs.inherited? == true
      assert summary.refs.found? == true
      assert summary.refs.source_impl_id == ctx.parent_impl.id
    end

    test "returns nothing inherited when all exists on child", ctx do
      child_branch = branch_fixture()
      tracked_branch_fixture(ctx.child_impl, %{branch: child_branch})

      child_spec =
        spec_fixture(ctx.product, %{
          branch: child_branch,
          feature_name: "test-feature",
          feature_version: "2.0.0"
        })

      spec_impl_state_fixture(child_spec, ctx.child_impl, %{
        states: %{
          "test.COMP.1" => %{"status" => "in_progress"}
        }
      })

      spec_impl_ref_fixture(child_spec, ctx.child_impl, %{
        refs: %{"test.COMP.1" => [%{"path" => "lib/bar.ex"}]}
      })

      summary = Specs.get_inheritance_summary("test-feature", ctx.child_impl.id)

      assert summary.spec.inherited? == false
      assert summary.spec.found? == true
      assert summary.spec.source_impl_id == ctx.child_impl.id

      assert summary.states.inherited? == false
      assert summary.states.found? == true
      assert summary.states.source_impl_id == ctx.child_impl.id

      assert summary.refs.inherited? == false
      assert summary.refs.found? == true
      assert summary.refs.source_impl_id == ctx.child_impl.id
    end

    test "returns mixed inheritance when some resources inherited", ctx do
      # Only inherit spec from parent, create local states
      child_branch = branch_fixture()
      tracked_branch_fixture(ctx.child_impl, %{branch: child_branch})

      _child_spec =
        spec_fixture(ctx.product, %{
          branch: child_branch,
          feature_name: "test-feature",
          feature_version: "2.0.0"
        })

      # Create states on parent (will be inherited since child has no states)
      spec_impl_state_fixture(ctx.parent_spec, ctx.parent_impl, %{
        states: %{"test.COMP.1" => %{"status" => "completed"}}
      })

      summary = Specs.get_inheritance_summary("test-feature", ctx.child_impl.id)

      # Spec is local
      assert summary.spec.inherited? == false

      # States inherited from parent
      assert summary.states.inherited? == true
      assert summary.states.source_impl_id == ctx.parent_impl.id

      # Refs not found anywhere
      assert summary.refs.found? == false
      assert summary.refs.inherited? == true
      assert summary.refs.source_impl_id == nil
    end

    test "returns nothing found when nothing exists anywhere", ctx do
      summary = Specs.get_inheritance_summary("nonexistent-feature", ctx.child_impl.id)

      refute summary.spec.found?
      assert summary.spec.inherited? == true
      assert summary.spec.source_impl_id == nil

      refute summary.states.found?
      assert summary.states.inherited? == true
      assert summary.states.source_impl_id == nil

      refute summary.refs.found?
      assert summary.refs.inherited? == true
      assert summary.refs.source_impl_id == nil
    end
  end

  describe "batch_resolve_specs_for_implementations/2" do
    setup do
      team = team_fixture()
      product = product_fixture(team)

      parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      child_impl =
        implementation_fixture(product, %{
          name: "child-impl",
          parent_implementation_id: parent_impl.id
        })

      parent_branch = branch_fixture()
      tracked_branch_fixture(parent_impl, %{branch: parent_branch})

      parent_spec =
        spec_fixture(product, %{branch: parent_branch, feature_name: "shared-feature"})

      %{
        team: team,
        product: product,
        parent_impl: parent_impl,
        child_impl: child_impl,
        parent_spec: parent_spec
      }
    end

    test "returns spec for each (feature_name, impl_id) pair", ctx do
      results =
        Specs.batch_resolve_specs_for_implementations(
          ["shared-feature"],
          [ctx.parent_impl, ctx.child_impl]
        )

      # Both should find the same spec from parent
      assert results[{"shared-feature", ctx.parent_impl.id}].id == ctx.parent_spec.id
      assert results[{"shared-feature", ctx.child_impl.id}].id == ctx.parent_spec.id
    end

    test "returns :not_found when spec not in ancestor tree", ctx do
      # product-view.MATRIX.8: If feature can't be found in ancestor tree, render 'n/a'
      results =
        Specs.batch_resolve_specs_for_implementations(
          ["nonexistent-feature"],
          [ctx.child_impl]
        )

      assert results[{"nonexistent-feature", ctx.child_impl.id}] == :not_found
    end

    test "respects inheritance with child precedence", ctx do
      # Create child-specific spec (different version to avoid unique constraint)
      child_branch = branch_fixture()
      tracked_branch_fixture(ctx.child_impl, %{branch: child_branch})

      child_spec =
        spec_fixture(ctx.product, %{
          branch: child_branch,
          feature_name: "shared-feature",
          feature_version: "2.0.0"
        })

      results =
        Specs.batch_resolve_specs_for_implementations(
          ["shared-feature"],
          [ctx.parent_impl, ctx.child_impl]
        )

      # Parent has parent's spec
      assert results[{"shared-feature", ctx.parent_impl.id}].id == ctx.parent_spec.id
      # Child has child's spec (takes precedence)
      assert results[{"shared-feature", ctx.child_impl.id}].id == child_spec.id
    end
  end

  describe "batch_get_feature_impl_completion/2 with inheritance" do
    setup do
      team = team_fixture()
      product = product_fixture(team)

      parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      child_impl =
        implementation_fixture(product, %{
          name: "child-impl",
          parent_implementation_id: parent_impl.id
        })

      branch = branch_fixture()
      tracked_branch_fixture(parent_impl, %{branch: branch})
      tracked_branch_fixture(child_impl, %{branch: branch})

      spec = spec_fixture(product, %{branch: branch, feature_name: "test-feature"})

      %{
        team: team,
        product: product,
        parent_impl: parent_impl,
        child_impl: child_impl,
        spec: spec
      }
    end

    test "uses direct states when available", ctx do
      # Create states directly on child
      spec_impl_state_fixture(ctx.spec, ctx.child_impl, %{
        states: %{
          "test.COMP.1" => %{"status" => "completed"},
          "test.COMP.2" => %{"status" => "pending"}
        }
      })

      results =
        Specs.batch_get_feature_impl_completion(
          ["test-feature"],
          [ctx.child_impl]
        )

      # feature-impl-view.INHERITANCE.3: All-or-nothing, child has its own states
      assert results[{"test-feature", ctx.child_impl.id}] == %{completed: 1, total: 2}
    end

    test "inherits states from parent when not available on child", ctx do
      # Create states only on parent
      spec_impl_state_fixture(ctx.spec, ctx.parent_impl, %{
        states: %{
          "test.COMP.1" => %{"status" => "completed"},
          "test.COMP.2" => %{"status" => "completed"},
          "test.COMP.3" => %{"status" => "pending"}
        }
      })

      results =
        Specs.batch_get_feature_impl_completion(
          ["test-feature"],
          [ctx.child_impl]
        )

      # feature-impl-view.MAIN.3: Status column shows inherited state
      # data-model.INHERITANCE.4: States inherit from parent
      assert results[{"test-feature", ctx.child_impl.id}] == %{completed: 2, total: 3}
    end

    test "returns zero counts when no states anywhere", ctx do
      results =
        Specs.batch_get_feature_impl_completion(
          ["test-feature"],
          [ctx.child_impl]
        )

      assert results[{"test-feature", ctx.child_impl.id}] == %{completed: 0, total: 0}
    end

    test "can disable inheritance with option", ctx do
      # Create states only on parent
      spec_impl_state_fixture(ctx.spec, ctx.parent_impl, %{
        states: %{"test.COMP.1" => %{"status" => "completed"}}
      })

      # With inheritance disabled
      results =
        Specs.batch_get_feature_impl_completion(
          ["test-feature"],
          [ctx.child_impl],
          inheritance: false
        )

      # Should return empty since child has no direct states
      assert results[{"test-feature", ctx.child_impl.id}] == %{completed: 0, total: 0}
    end
  end

  describe "batch_get_spec_impl_completion/2 with inheritance" do
    setup do
      team = team_fixture()
      product = product_fixture(team)

      parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      child_impl =
        implementation_fixture(product, %{
          name: "child-impl",
          parent_implementation_id: parent_impl.id
        })

      branch = branch_fixture()
      tracked_branch_fixture(parent_impl, %{branch: branch})
      tracked_branch_fixture(child_impl, %{branch: branch})

      spec =
        spec_fixture(product, %{
          branch: branch,
          feature_name: "test-feature",
          requirements: %{
            "test.COMP.1" => %{},
            "test.COMP.2" => %{},
            "test.COMP.3" => %{}
          }
        })

      %{
        team: team,
        product: product,
        parent_impl: parent_impl,
        child_impl: child_impl,
        spec: spec
      }
    end

    test "uses direct states when available", ctx do
      spec_impl_state_fixture(ctx.spec, ctx.child_impl, %{
        states: %{
          "test.COMP.1" => %{"status" => "completed"},
          "test.COMP.2" => %{"status" => "completed"}
        }
      })

      results =
        Specs.batch_get_spec_impl_completion(
          [ctx.spec],
          [ctx.child_impl]
        )

      # 2 of 3 requirements completed
      assert results[{ctx.spec.id, ctx.child_impl.id}] == %{completed: 2, total: 3}
    end

    test "inherits states from parent when not available on child", ctx do
      spec_impl_state_fixture(ctx.spec, ctx.parent_impl, %{
        states: %{
          "test.COMP.1" => %{"status" => "completed"},
          "test.COMP.2" => %{"status" => "accepted"},
          "test.COMP.3" => %{"status" => "pending"}
        }
      })

      results =
        Specs.batch_get_spec_impl_completion(
          [ctx.spec],
          [ctx.child_impl]
        )

      # 2 of 3 completed (completed + accepted both count)
      assert results[{ctx.spec.id, ctx.child_impl.id}] == %{completed: 2, total: 3}
    end

    test "can disable inheritance with option", ctx do
      spec_impl_state_fixture(ctx.spec, ctx.parent_impl, %{
        states: %{"test.COMP.1" => %{"status" => "completed"}}
      })

      results =
        Specs.batch_get_spec_impl_completion(
          [ctx.spec],
          [ctx.child_impl],
          inheritance: false
        )

      # No inheritance means 0 completion
      assert results[{ctx.spec.id, ctx.child_impl.id}] == %{completed: 0, total: 3}
    end
  end
end
