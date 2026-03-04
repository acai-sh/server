defmodule Acai.Implementations.ImplementationTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Implementations.Implementation

  describe "changeset/2" do
    test "valid with required fields" do
      cs = Implementation.changeset(%Implementation{}, %{name: "Production", is_active: true})
      assert cs.valid?
    end

    # DATA.IMPLS.3
    test "invalid without name" do
      cs = Implementation.changeset(%Implementation{}, %{is_active: true})
      refute cs.valid?
      assert %{name: [_ | _]} = errors_on(cs)
    end

    # DATA.IMPLS.4
    test "accepts optional description" do
      cs =
        Implementation.changeset(%Implementation{}, %{
          name: "Production",
          is_active: true,
          description: "The main production implementation."
        })

      assert cs.valid?
    end

    # DATA.IMPLS.5
    test "is_active defaults to true" do
      assert %Implementation{}.is_active == true
    end

    # DATA.IMPLS.1
    test "uses UUIDv7 primary key" do
      assert Implementation.__schema__(:primary_key) == [:id]
      assert Implementation.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database constraints" do
    # DATA.IMPLS.7
    test "composite unique constraint on (spec_id, name)" do
      team = team_fixture()
      spec = spec_fixture(team)
      implementation_fixture(spec, %{name: "Production"})

      {:error, cs} =
        Implementation.changeset(%Implementation{}, %{name: "Production", is_active: true})
        |> Ecto.Changeset.put_change(:spec_id, spec.id)
        |> Ecto.Changeset.put_change(:team_id, spec.team_id)
        |> Acai.Repo.insert()

      assert %{spec_id: [_ | _]} = errors_on(cs)
    end
  end
end
