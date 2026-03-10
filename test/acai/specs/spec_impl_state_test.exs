defmodule Acai.Specs.SpecImplStateTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs.SpecImplState

  describe "changeset/2" do
    test "valid with all required fields" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      attrs = %{
        states: %{
          "feature.COMP.1" => %{
            "status" => "pending",
            "comment" => "Initial state",
            "metadata" => %{},
            "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        },
        spec_id: spec.id,
        implementation_id: impl.id
      }

      cs = SpecImplState.changeset(%SpecImplState{}, attrs)

      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = SpecImplState.changeset(%SpecImplState{}, %{})
      refute cs.valid?

      # states has default value %{}, so implementation_id and spec_id are the actual required errors
      assert %{implementation_id: [_ | _]} = errors_on(cs)
      assert %{spec_id: [_ | _]} = errors_on(cs)
    end

    # data-model.SPEC_IMPL_STATES.1
    test "uses UUIDv7 primary key" do
      assert SpecImplState.__schema__(:primary_key) == [:id]
      assert SpecImplState.__schema__(:type, :id) == Acai.UUIDv7
    end

    # data-model.SPEC_IMPL_STATES.4
    test "accepts empty states map" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      attrs = %{states: %{}, spec_id: spec.id, implementation_id: impl.id}

      cs = SpecImplState.changeset(%SpecImplState{}, attrs)

      assert cs.valid?
    end

    # data-model.SPEC_IMPL_STATES.4-3
    test "accepts all valid status values" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      valid_statuses = ["pending", "in_progress", "blocked", "completed", "rejected"]

      for status <- valid_statuses do
        attrs = %{
          states: %{
            "feature.COMP.1" => %{"status" => status}
          },
          spec_id: spec.id,
          implementation_id: impl.id
        }

        cs = SpecImplState.changeset(%SpecImplState{}, attrs)

        assert cs.valid?, "Expected status #{status} to be valid"
      end
    end
  end

  describe "database constraint: SPEC_IMPL_STATES.5 (implementation_id, spec_id)" do
    test "enforces composite unique constraint" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      {:ok, _} =
        SpecImplState.changeset(%SpecImplState{}, %{
          states: %{},
          spec_id: spec.id,
          implementation_id: impl.id
        })
        |> Acai.Repo.insert()

      {:error, cs} =
        SpecImplState.changeset(%SpecImplState{}, %{
          states: %{"a" => %{"status" => "pending"}},
          spec_id: spec.id,
          implementation_id: impl.id
        })
        |> Acai.Repo.insert()

      assert %{implementation_id: [_ | _]} = errors_on(cs)
    end
  end
end
