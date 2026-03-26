defmodule Acai.ProductsTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Products
  alias Acai.Products.Product

  setup do
    team = team_fixture()
    {:ok, team: team}
  end

  describe "list_products/2" do
    test "returns empty list when no products exist", %{team: team} do
      current_scope = %{user: %{id: 1}}
      assert Products.list_products(current_scope, team) == []
    end

    test "returns products for the team", %{team: team} do
      current_scope = %{user: %{id: 1}}
      product = product_fixture(team, %{name: "my-product"})

      assert [^product] = Products.list_products(current_scope, team)
    end

    test "does not return products from other teams" do
      current_scope = %{user: %{id: 1}}
      team1 = team_fixture()
      team2 = team_fixture()
      product_fixture(team1, %{name: "product-1"})

      assert Products.list_products(current_scope, team2) == []
    end
  end

  describe "get_product!/1" do
    test "returns the product by id", %{team: team} do
      product = product_fixture(team)
      assert Products.get_product!(product.id).id == product.id
    end

    test "raises when not found" do
      assert_raise Ecto.NoResultsError, fn ->
        Products.get_product!(Acai.UUIDv7.autogenerate())
      end
    end
  end

  describe "get_product_by_name!/2" do
    test "returns the product by team and name", %{team: team} do
      product = product_fixture(team, %{name: "my-product"})
      assert Products.get_product_by_name!(team, "my-product").id == product.id
    end

    test "raises when not found", %{team: team} do
      assert_raise Ecto.NoResultsError, fn ->
        Products.get_product_by_name!(team, "nonexistent")
      end
    end
  end

  describe "create_product/3" do
    test "creates a product linked to the team", %{team: team} do
      current_scope = %{user: %{id: 1}}
      attrs = %{name: "new-product", description: "A new product"}

      assert {:ok, %Product{} = product} = Products.create_product(current_scope, team, attrs)
      assert product.name == "new-product"
      assert product.description == "A new product"
      assert product.team_id == team.id
      assert product.is_active == true
    end

    test "returns error changeset when attrs are invalid", %{team: team} do
      current_scope = %{user: %{id: 1}}
      assert {:error, changeset} = Products.create_product(current_scope, team, %{name: ""})
      refute changeset.valid?
    end

    test "returns error on duplicate name within same team", %{team: team} do
      current_scope = %{user: %{id: 1}}
      Products.create_product(current_scope, team, %{name: "my-product"})

      assert {:error, changeset} =
               Products.create_product(current_scope, team, %{name: "my-product"})

      refute changeset.valid?
    end
  end

  describe "update_product/2" do
    test "updates the product", %{team: team} do
      product = product_fixture(team, %{name: "old-name"})
      attrs = %{name: "new-name", description: "Updated description"}

      assert {:ok, %Product{} = updated} = Products.update_product(product, attrs)
      assert updated.name == "new-name"
      assert updated.description == "Updated description"
    end

    test "returns error changeset when attrs are invalid", %{team: team} do
      product = product_fixture(team)
      assert {:error, changeset} = Products.update_product(product, %{name: ""})
      refute changeset.valid?
    end
  end

  describe "delete_product/1" do
    test "deletes the product", %{team: team} do
      product = product_fixture(team)
      assert {:ok, %Product{}} = Products.delete_product(product)
      assert_raise Ecto.NoResultsError, fn -> Products.get_product!(product.id) end
    end
  end

  describe "change_product/2" do
    test "returns a changeset for the product", %{team: team} do
      product = product_fixture(team)
      cs = Products.change_product(product, %{name: "new-name"})
      assert cs.changes == %{name: "new-name"}
    end

    test "returns a blank changeset with no attrs", %{team: team} do
      product = product_fixture(team)
      cs = Products.change_product(product)
      assert cs.changes == %{}
    end
  end

  describe "get_team_by_name/1" do
    test "returns {:ok, team} when team exists" do
      _team = team_fixture(%{name: "test-team-123"})

      assert {:ok, %Acai.Teams.Team{name: "test-team-123"}} =
               Products.get_team_by_name("test-team-123")
    end

    test "returns {:error, :not_found} when team does not exist" do
      assert {:error, :not_found} = Products.get_team_by_name("nonexistent-team-xyz")
    end
  end

  describe "get_product_from_list/3" do
    test "returns {:ok, product} when product exists in list", %{team: team} do
      product = product_fixture(team, %{name: "my-product"})
      products = Products.list_products(%{user: %{id: 1}}, team)

      assert {:ok, %Product{id: product_id}} =
               Products.get_product_from_list(products, team, "my-product")

      assert product_id == product.id
    end

    test "returns {:ok, product} with case-insensitive matching", %{team: team} do
      product = product_fixture(team, %{name: "my-product"})
      products = Products.list_products(%{user: %{id: 1}}, team)

      assert {:ok, %Product{id: product_id}} =
               Products.get_product_from_list(products, team, "MY-PRODUCT")

      assert product_id == product.id
    end

    test "returns {:error, :not_found} when product not in list", %{team: team} do
      _product = product_fixture(team, %{name: "existing-product"})
      products = Products.list_products(%{user: %{id: 1}}, team)

      assert {:error, :not_found} =
               Products.get_product_from_list(products, team, "nonexistent-product")
    end

    test "returns {:error, :not_found} when product belongs to different team", %{team: team1} do
      team2 = team_fixture(%{name: "other-team"})
      _product = product_fixture(team2, %{name: "other-product"})
      products = Products.list_products(%{user: %{id: 1}}, team1)

      assert {:error, :not_found} =
               Products.get_product_from_list(products, team1, "other-product")
    end
  end

  describe "load_product_page/2" do
    test "returns empty state when product has no specs and no implementations", %{team: team} do
      product = product_fixture(team)

      page_data = Products.load_product_page(product)

      assert page_data.product.id == product.id
      assert page_data.active_implementations == []
      assert page_data.features_by_name == []
      assert page_data.spec_impl_completion == %{}
      assert page_data.feature_availability == %{}
      assert page_data.empty? == true
      assert page_data.no_features? == true
      assert page_data.no_implementations? == true
    end

    test "returns empty state when product has no active implementations", %{team: team} do
      product = product_fixture(team)
      # Create inactive implementation
      _inactive_impl = implementation_fixture(product, %{is_active: false})
      # Create spec
      _spec = spec_fixture(product)

      page_data = Products.load_product_page(product)

      assert page_data.empty? == true
      assert page_data.no_features? == false
      assert page_data.no_implementations? == true
    end

    test "returns matrix data with specs and active implementations", %{team: team} do
      import Acai.DataModelFixtures

      product = product_fixture(team)
      branch = branch_fixture(team)
      implementation = implementation_fixture(product, %{is_active: true})
      _tracked_branch = tracked_branch_fixture(implementation, branch: branch)

      spec =
        spec_fixture(product,
          branch: branch,
          feature_name: "test-feature",
          feature_description: "A test feature",
          requirements: %{"TEST.1" => %{}, "TEST.2" => %{}},
          path: "features/test/feature.yaml"
        )

      page_data = Products.load_product_page(product)

      # Check structure
      assert page_data.empty? == false
      assert page_data.no_features? == false
      assert page_data.no_implementations? == false

      # Check features_by_name
      assert [%{name: "test-feature", description: "A test feature", specs: specs}] =
               page_data.features_by_name

      assert length(specs) == 1
      assert hd(specs).id == spec.id

      # Check active_implementations
      assert [%{id: impl_id}] = page_data.active_implementations
      assert impl_id == implementation.id

      # Check availability - feature should be available since spec is on tracked branch
      assert page_data.feature_availability[{"test-feature", implementation.id}] == true

      # Check completion - should be 0/2 since no states exist
      assert page_data.spec_impl_completion[{spec.id, implementation.id}] == %{
               completed: 0,
               total: 2
             }
    end

    test "returns completion data with inherited states", %{team: team} do
      import Acai.DataModelFixtures

      product = product_fixture(team)
      branch = branch_fixture(team)

      # Create parent implementation with tracked branch
      parent_impl = implementation_fixture(product, %{is_active: true, name: "Parent"})
      _parent_tracked = tracked_branch_fixture(parent_impl, branch: branch)

      # Create child implementation (no tracked branch, will inherit)
      child_impl =
        implementation_fixture(product, %{
          is_active: true,
          name: "Child",
          parent_implementation_id: parent_impl.id
        })

      spec =
        spec_fixture(product,
          branch: branch,
          feature_name: "test-feature",
          requirements: %{"TEST.1" => %{}},
          path: "features/test/feature.yaml"
        )

      # Create feature_impl_state on parent implementation
      _state =
        spec_impl_state_fixture(spec, parent_impl,
          states: %{"TEST.1" => %{"status" => "completed"}}
        )

      page_data = Products.load_product_page(product)

      # Child should inherit the completed state from parent
      assert page_data.spec_impl_completion[{spec.id, child_impl.id}] == %{completed: 1, total: 1}
    end

    test "respects direction option for implementation ordering", %{team: team} do
      product = product_fixture(team)

      # Create implementations with names that would sort differently
      _impl_a = implementation_fixture(product, %{is_active: true, name: "A-Implementation"})
      _impl_b = implementation_fixture(product, %{is_active: true, name: "B-Implementation"})

      # LTR (default) should order by name ascending
      page_data_ltr = Products.load_product_page(product, direction: :ltr)
      names_ltr = Enum.map(page_data_ltr.active_implementations, & &1.name)
      assert names_ltr == ["A-Implementation", "B-Implementation"]
    end
  end
end
