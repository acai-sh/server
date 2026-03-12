defmodule Acai.SpecsTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs
  alias Acai.Specs.{Spec, FeatureImplState, FeatureImplRef}

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
      current_scope = %{user: %{id: 1}}

      attrs = %{
        repo_uri: "github.com/acai-sh/server",
        branch_name: "main",
        last_seen_commit: "abc123",
        parsed_at: DateTime.utc_now(),
        feature_name: "new-feature"
      }

      assert {:ok, %Spec{} = spec} = Specs.create_spec(current_scope, team, product, attrs)
      assert spec.feature_name == "new-feature"
      assert spec.product_id == product.id
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

  # --- FeatureImplRef tests ---

  describe "get_feature_impl_ref/2" do
    test "returns the ref for feature_name and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      ref_record = spec_impl_ref_fixture(spec, impl)

      assert Specs.get_feature_impl_ref(spec.feature_name, impl).id == ref_record.id
    end

    test "returns nil when no ref exists" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      assert Specs.get_feature_impl_ref(spec.feature_name, impl) == nil
    end
  end

  describe "create_feature_impl_ref/3" do
    test "creates a ref for feature_name and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      attrs = %{
        refs: %{
          "test.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "lib/foo.ex",
              "loc" => "10:5",
              "is_test" => false
            }
          ]
        },
        agent: "github-action",
        commit: "abc123",
        pushed_at: DateTime.utc_now()
      }

      assert {:ok, %FeatureImplRef{} = ref_record} =
               Specs.create_feature_impl_ref(spec.feature_name, impl, attrs)

      assert ref_record.feature_name == spec.feature_name
      assert ref_record.implementation_id == impl.id
      assert ref_record.agent == "github-action"
    end

    test "returns error changeset when attrs are invalid" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      assert {:error, changeset} =
               Specs.create_feature_impl_ref(spec.feature_name, impl, %{refs: nil})

      refute changeset.valid?
    end
  end

  describe "update_feature_impl_ref/2" do
    test "updates the ref" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      ref_record = spec_impl_ref_fixture(spec, impl)

      new_refs = %{
        "test.COMP.1" => [
          %{
            "repo" => "github.com/org/repo",
            "path" => "lib/bar.ex",
            "loc" => "20:10",
            "is_test" => true
          }
        ]
      }

      assert {:ok, %FeatureImplRef{} = updated} =
               Specs.update_feature_impl_ref(ref_record, %{refs: new_refs})

      assert updated.refs["test.COMP.1"] |> hd() |> Map.get("path") == "lib/bar.ex"
    end
  end

  describe "upsert_feature_impl_ref/3" do
    test "inserts a new ref when none exists" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      attrs = %{
        refs: %{"a" => [%{"path" => "lib/foo.ex"}]},
        agent: "cli",
        commit: "def456",
        pushed_at: DateTime.utc_now()
      }

      assert {:ok, %FeatureImplRef{} = ref_record} =
               Specs.upsert_feature_impl_ref(spec.feature_name, impl, attrs)

      assert ref_record.feature_name == spec.feature_name
      assert ref_record.implementation_id == impl.id
    end

    test "updates existing ref on conflict" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      {:ok, original} =
        Specs.upsert_feature_impl_ref(spec.feature_name, impl, %{
          refs: %{"a" => [%{"path" => "lib/foo.ex"}]},
          agent: "cli",
          commit: "abc",
          pushed_at: DateTime.utc_now()
        })

      {:ok, updated} =
        Specs.upsert_feature_impl_ref(spec.feature_name, impl, %{
          refs: %{"a" => [%{"path" => "lib/bar.ex"}]},
          agent: "github-action",
          commit: "def",
          pushed_at: DateTime.utc_now()
        })

      assert updated.id == original.id
      assert updated.agent == "github-action"
      assert updated.refs["a"] |> hd() |> Map.get("path") == "lib/bar.ex"
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
    test "returns the ref for spec and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()
      ref_record = spec_impl_ref_fixture(spec, impl)

      assert Specs.get_spec_impl_ref(spec, impl).id == ref_record.id
    end
  end

  describe "create_spec_impl_ref/3 (legacy)" do
    test "creates a ref for spec and implementation" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      attrs = %{
        refs: %{
          "test.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "lib/foo.ex",
              "loc" => "10:5",
              "is_test" => false
            }
          ]
        },
        agent: "github-action",
        commit: "abc123",
        pushed_at: DateTime.utc_now()
      }

      assert {:ok, %FeatureImplRef{} = ref_record} = Specs.create_spec_impl_ref(spec, impl, attrs)
      assert ref_record.feature_name == spec.feature_name
      assert ref_record.implementation_id == impl.id
    end
  end

  describe "upsert_spec_impl_ref/3 (legacy)" do
    test "inserts a new ref when none exists" do
      %{spec: spec, impl: impl} = setup_spec_chain()

      attrs = %{
        refs: %{"a" => [%{"path" => "lib/foo.ex"}]},
        agent: "cli",
        commit: "def456",
        pushed_at: DateTime.utc_now()
      }

      assert {:ok, %FeatureImplRef{} = ref_record} = Specs.upsert_spec_impl_ref(spec, impl, attrs)
      assert ref_record.feature_name == spec.feature_name
      assert ref_record.implementation_id == impl.id
    end
  end
end
