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

      assert slug =~ ~r/^production-server\+[a-f0-9]{32}$/
    end
  end

  describe "get_implementation_by_slug/1" do
    test "returns the implementation by slug", %{product: product} do
      impl = implementation_fixture(product, %{name: "Production"})
      slug = Implementations.implementation_slug(impl)

      assert Implementations.get_implementation_by_slug(slug).id == impl.id
    end

    test "returns nil for invalid slug format" do
      assert Implementations.get_implementation_by_slug("invalid-slug") == nil
    end

    test "returns nil when not found" do
      fake_slug = "test+" <> String.duplicate("a", 32)
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
    test "returns branches for the implementation", %{product: product} do
      impl = implementation_fixture(product)
      branch = tracked_branch_fixture(impl)

      assert [^branch] = Implementations.list_tracked_branches(impl)
    end
  end

  describe "create_tracked_branch/2" do
    test "creates a branch for the implementation", %{product: product} do
      impl = implementation_fixture(product)

      attrs = %{
        repo_uri: "github.com/org/repo",
        branch_name: "feature-branch",
        last_seen_commit: "def789"
      }

      assert {:ok, branch} = Implementations.create_tracked_branch(impl, attrs)
      assert branch.implementation_id == impl.id
      assert branch.repo_uri == "github.com/org/repo"
      assert branch.last_seen_commit == "def789"
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
      team = product.team
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      spec_impl_state_fixture(spec, impl, %{
        states: %{
          "feat.1" => %{"status" => "pending"},
          "feat.2" => %{"status" => "in_progress"},
          "feat.3" => %{"status" => "completed"},
          "feat.4" => %{"status" => "completed"},
          "feat.5" => %{"status" => "blocked"}
        }
      })

      counts = Implementations.get_spec_impl_state_counts(impl)

      assert counts["pending"] == 1
      assert counts["in_progress"] == 1
      assert counts["completed"] == 2
      assert counts["blocked"] == 1
      assert counts["rejected"] == 0
    end

    test "returns zero counts when no states exist", %{product: product} do
      impl = implementation_fixture(product)

      counts = Implementations.get_spec_impl_state_counts(impl)

      assert counts["pending"] == 0
      assert counts["in_progress"] == 0
      assert counts["completed"] == 0
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
          "feat.1" => %{"status" => "pending"},
          "feat.2" => %{"status" => "completed"}
        }
      })

      spec_impl_state_fixture(spec, impl2, %{
        states: %{
          "feat.1" => %{"status" => "in_progress"}
        }
      })

      counts = Implementations.batch_get_spec_impl_state_counts([impl1, impl2])

      assert counts[impl1.id]["pending"] == 1
      assert counts[impl1.id]["completed"] == 1
      assert counts[impl2.id]["in_progress"] == 1
    end
  end

  describe "list_active_implementations_for_specs/1" do
    test "returns active implementations for specs through product", %{
      team: team,
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
end
