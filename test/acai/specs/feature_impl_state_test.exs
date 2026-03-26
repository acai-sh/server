defmodule Acai.Specs.FeatureImplStateTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs.FeatureImplState

  describe "changeset/2" do
    test "valid with all required fields" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      attrs = %{
        states: %{
          "feature.COMP.1" => %{
            "status" => "assigned",
            "comment" => "Initial state",
            "metadata" => %{},
            "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        },
        feature_name: spec.feature_name,
        implementation_id: impl.id
      }

      cs = FeatureImplState.changeset(%FeatureImplState{}, attrs)

      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = FeatureImplState.changeset(%FeatureImplState{}, %{})
      refute cs.valid?

      # states has default value %{}, so implementation_id and feature_name are the actual required errors
      assert %{implementation_id: [_ | _]} = errors_on(cs)
      assert %{feature_name: [_ | _]} = errors_on(cs)
    end

    # data-model.FEATURE_IMPL_STATES.1
    test "uses UUIDv7 primary key" do
      assert FeatureImplState.__schema__(:primary_key) == [:id]
      assert FeatureImplState.__schema__(:type, :id) == Acai.UUIDv7
    end

    # data-model.FEATURE_IMPL_STATES.4
    test "accepts empty states map" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      attrs = %{states: %{}, feature_name: spec.feature_name, implementation_id: impl.id}

      cs = FeatureImplState.changeset(%FeatureImplState{}, attrs)

      assert cs.valid?
    end

    # data-model.FEATURE_IMPL_STATES.4-3
    test "accepts all valid status values" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      valid_statuses = ["assigned", "blocked", "completed", "rejected", "accepted"]

      for status <- valid_statuses do
        attrs = %{
          states: %{
            "feature.COMP.1" => %{"status" => status}
          },
          feature_name: spec.feature_name,
          implementation_id: impl.id
        }

        cs = FeatureImplState.changeset(%FeatureImplState{}, attrs)

        assert cs.valid?, "Expected status #{status} to be valid"
      end
    end

    # data-model.FEATURE_IMPL_STATES.3-1
    test "feature_name must be url-safe" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      attrs = %{
        states: %{},
        feature_name: "invalid feature name!",
        implementation_id: impl.id
      }

      cs = FeatureImplState.changeset(%FeatureImplState{}, attrs)

      refute cs.valid?
      assert %{feature_name: [_ | _]} = errors_on(cs)
    end
  end

  describe "database constraint: FEATURE_IMPL_STATES.5 (implementation_id, feature_name)" do
    test "enforces composite unique constraint" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      {:ok, _} =
        FeatureImplState.changeset(%FeatureImplState{}, %{
          states: %{},
          feature_name: spec.feature_name,
          implementation_id: impl.id
        })
        |> Acai.Repo.insert()

      {:error, cs} =
        FeatureImplState.changeset(%FeatureImplState{}, %{
          states: %{"a" => %{"status" => "assigned"}},
          feature_name: spec.feature_name,
          implementation_id: impl.id
        })
        |> Acai.Repo.insert()

      assert %{implementation_id: [_ | _]} = errors_on(cs)
    end

    test "allows same feature_name across different implementations" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl1 = implementation_fixture(product)
      impl2 = implementation_fixture(product, %{name: "Staging"})

      {:ok, _} =
        FeatureImplState.changeset(%FeatureImplState{}, %{
          states: %{},
          feature_name: spec.feature_name,
          implementation_id: impl1.id
        })
        |> Acai.Repo.insert()

      {:ok, _} =
        FeatureImplState.changeset(%FeatureImplState{}, %{
          states: %{},
          feature_name: spec.feature_name,
          implementation_id: impl2.id
        })
        |> Acai.Repo.insert()
    end
  end
end
