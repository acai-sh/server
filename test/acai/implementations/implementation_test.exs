defmodule Acai.Implementations.ImplementationTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Implementations.Implementation

  describe "changeset/2" do
    test "valid with required fields" do
      team = team_fixture()
      product = product_fixture(team)

      cs =
        Implementation.changeset(%Implementation{}, %{
          name: "Production",
          is_active: true,
          product_id: product.id,
          team_id: team.id
        })

      assert cs.valid?
    end

    # data-model.IMPLS.3
    test "invalid without name" do
      cs = Implementation.changeset(%Implementation{}, %{is_active: true})
      refute cs.valid?
      assert %{name: [_ | _]} = errors_on(cs)
    end

    # data-model.IMPLS.4
    test "accepts optional description" do
      team = team_fixture()
      product = product_fixture(team)

      cs =
        Implementation.changeset(%Implementation{}, %{
          name: "Production",
          is_active: true,
          description: "The main production implementation.",
          product_id: product.id,
          team_id: team.id
        })

      assert cs.valid?
    end

    # data-model.IMPLS.5
    test "is_active defaults to true" do
      assert %Implementation{}.is_active == true
    end

    # data-model.IMPLS.1
    test "uses UUIDv7 primary key" do
      assert Implementation.__schema__(:primary_key) == [:id]
      assert Implementation.__schema__(:type, :id) == Acai.UUIDv7
    end

    # data-model.IMPLS.7
    test "accepts optional parent_implementation_id" do
      team = team_fixture()
      product = product_fixture(team)
      parent = implementation_fixture(product, %{name: "parent"})

      cs =
        Implementation.changeset(%Implementation{}, %{
          name: "child",
          is_active: true,
          product_id: product.id,
          team_id: team.id,
          parent_implementation_id: parent.id
        })

      assert cs.valid?
    end
  end

  describe "database constraints" do
    # data-model.IMPLS.8
    test "composite unique constraint on (product_id, name)" do
      team = team_fixture()
      product = product_fixture(team)
      implementation_fixture(product, %{name: "Production"})

      {:error, cs} =
        Implementation.changeset(%Implementation{}, %{
          name: "Production",
          is_active: true,
          product_id: product.id,
          team_id: team.id
        })
        |> Acai.Repo.insert()

      assert %{product_id: [_ | _]} = errors_on(cs)
    end
  end
end
