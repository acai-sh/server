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
end
