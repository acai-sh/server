defmodule Acai.Specs.FeatureImplRefTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs.FeatureImplRef

  describe "changeset/2" do
    test "valid with all required fields" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      attrs = %{
        refs: %{
          "feature.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "lib/my_app/module.ex",
              "loc" => "42:10",
              "is_test" => false
            }
          ]
        },
        agent: "github-action",
        commit: "abc123def456",
        pushed_at: DateTime.utc_now(),
        feature_name: spec.feature_name,
        implementation_id: impl.id
      }

      cs = FeatureImplRef.changeset(%FeatureImplRef{}, attrs)

      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = FeatureImplRef.changeset(%FeatureImplRef{}, %{})
      refute cs.valid?
      # refs has default value %{}, so other fields show errors
      assert %{agent: [_ | _]} = errors_on(cs)
      assert %{commit: [_ | _]} = errors_on(cs)
      assert %{pushed_at: [_ | _]} = errors_on(cs)
      assert %{implementation_id: [_ | _]} = errors_on(cs)
      assert %{feature_name: [_ | _]} = errors_on(cs)
    end

    # data-model.FEATURE_IMPL_REFS.1
    test "uses UUIDv7 primary key" do
      assert FeatureImplRef.__schema__(:primary_key) == [:id]
      assert FeatureImplRef.__schema__(:type, :id) == Acai.UUIDv7
    end

    # data-model.FEATURE_IMPL_REFS.4
    test "accepts empty refs map" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      attrs = %{
        refs: %{},
        agent: "cli",
        commit: "abc123",
        pushed_at: DateTime.utc_now(),
        feature_name: spec.feature_name,
        implementation_id: impl.id
      }

      cs = FeatureImplRef.changeset(%FeatureImplRef{}, attrs)

      assert cs.valid?
    end

    # data-model.FEATURE_IMPL_REFS.4-2
    test "accepts multiple refs per ACID" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      attrs = %{
        refs: %{
          "feature.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "lib/a.ex",
              "loc" => "1:1",
              "is_test" => false
            },
            %{
              "repo" => "github.com/org/repo",
              "path" => "lib/b.ex",
              "loc" => "2:2",
              "is_test" => false
            }
          ]
        },
        agent: "github-action",
        commit: "abc123",
        pushed_at: DateTime.utc_now(),
        feature_name: spec.feature_name,
        implementation_id: impl.id
      }

      cs = FeatureImplRef.changeset(%FeatureImplRef{}, attrs)

      assert cs.valid?
    end

    # data-model.FEATURE_IMPL_REFS.5
    test "accepts various agent identifiers" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      agents = ["github-action", "@username", "robot-label", "cli", "ci-system"]

      for agent <- agents do
        attrs = %{
          refs: %{},
          agent: agent,
          commit: "abc123",
          pushed_at: DateTime.utc_now(),
          feature_name: spec.feature_name,
          implementation_id: impl.id
        }

        cs = FeatureImplRef.changeset(%FeatureImplRef{}, attrs)

        assert cs.valid?, "Expected agent #{agent} to be valid"
      end
    end

    # data-model.FEATURE_IMPL_REFS.3-1
    test "feature_name must be url-safe" do
      team = team_fixture()
      product = product_fixture(team)
      impl = implementation_fixture(product)

      attrs = %{
        refs: %{},
        agent: "cli",
        commit: "abc123",
        pushed_at: DateTime.utc_now(),
        feature_name: "invalid feature name!",
        implementation_id: impl.id
      }

      cs = FeatureImplRef.changeset(%FeatureImplRef{}, attrs)

      refute cs.valid?
      assert %{feature_name: [_ | _]} = errors_on(cs)
    end
  end

  describe "database constraint: FEATURE_IMPL_REFS.8 (implementation_id, feature_name)" do
    test "enforces composite unique constraint" do
      team = team_fixture()
      product = product_fixture(team)
      spec = spec_fixture(product)
      impl = implementation_fixture(product)

      {:ok, _} =
        FeatureImplRef.changeset(%FeatureImplRef{}, %{
          refs: %{},
          agent: "cli",
          commit: "abc123",
          pushed_at: DateTime.utc_now(),
          feature_name: spec.feature_name,
          implementation_id: impl.id
        })
        |> Acai.Repo.insert()

      {:error, cs} =
        FeatureImplRef.changeset(%FeatureImplRef{}, %{
          refs: %{"a" => [%{"path" => "lib/foo.ex"}]},
          agent: "cli",
          commit: "def456",
          pushed_at: DateTime.utc_now(),
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
        FeatureImplRef.changeset(%FeatureImplRef{}, %{
          refs: %{},
          agent: "cli",
          commit: "abc123",
          pushed_at: DateTime.utc_now(),
          feature_name: spec.feature_name,
          implementation_id: impl1.id
        })
        |> Acai.Repo.insert()

      {:ok, _} =
        FeatureImplRef.changeset(%FeatureImplRef{}, %{
          refs: %{},
          agent: "cli",
          commit: "abc123",
          pushed_at: DateTime.utc_now(),
          feature_name: spec.feature_name,
          implementation_id: impl2.id
        })
        |> Acai.Repo.insert()
    end
  end
end
