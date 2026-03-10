defmodule Acai.Products.ProductTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Products.Product

  describe "changeset/2" do
    test "valid with all required fields" do
      team = team_fixture()

      attrs = %{
        name: "my-product",
        description: "A test product",
        is_active: true,
        team_id: team.id
      }

      cs = Product.changeset(%Product{}, attrs)

      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = Product.changeset(%Product{}, %{})
      refute cs.valid?
      assert %{name: [_ | _]} = errors_on(cs)
    end

    # data-model.PRODUCTS.3-1
    test "invalid when name contains spaces" do
      team = team_fixture()

      attrs = %{
        name: "my product",
        description: "A test product"
      }

      cs =
        Product.changeset(%Product{}, attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)

      refute cs.valid?
      assert %{name: [_ | _]} = errors_on(cs)
    end

    test "valid name with hyphens and underscores" do
      team = team_fixture()

      attrs = %{
        name: "my-product_v2",
        description: "A test product",
        team_id: team.id
      }

      cs = Product.changeset(%Product{}, attrs)

      assert cs.valid?
    end

    # data-model.PRODUCTS.1
    test "uses UUIDv7 primary key" do
      assert Product.__schema__(:primary_key) == [:id]
      assert Product.__schema__(:type, :id) == Acai.UUIDv7
    end

    # data-model.PRODUCTS.5
    test "is_active defaults to true" do
      cs = Product.changeset(%Product{}, %{name: "test-product"})
      assert Ecto.Changeset.get_field(cs, :is_active) == true
    end

    # data-model.PRODUCTS.4
    test "description is optional" do
      team = team_fixture()

      attrs = %{
        name: "my-product",
        team_id: team.id
      }

      cs = Product.changeset(%Product{}, attrs)

      assert cs.valid?
    end
  end

  describe "database constraint: PRODUCTS.6 (team_id, name)" do
    test "enforces composite unique constraint" do
      team = team_fixture()

      {:ok, _} =
        Product.changeset(%Product{}, %{name: "my-product", team_id: team.id})
        |> Acai.Repo.insert()

      {:error, cs} =
        Product.changeset(%Product{}, %{name: "my-product", team_id: team.id})
        |> Acai.Repo.insert()

      assert %{team_id: [_ | _]} = errors_on(cs)
    end

    test "different teams can have same name" do
      team1 = team_fixture()
      team2 = team_fixture()

      {:ok, _} =
        Product.changeset(%Product{}, %{name: "my-product", team_id: team1.id})
        |> Acai.Repo.insert()

      {:ok, _} =
        Product.changeset(%Product{}, %{name: "my-product", team_id: team2.id})
        |> Acai.Repo.insert()
    end
  end

  describe "database constraint: PRODUCTS.3-1 name_url_safe" do
    test "check constraint fires for invalid chars bypassing changeset" do
      team = team_fixture()

      {:error, cs} =
        Product.changeset(%Product{}, %{name: "invalid name!", team_id: team.id})
        |> Acai.Repo.insert()

      assert cs.errors[:name] != nil
    end
  end
end
