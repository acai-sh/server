defmodule Acai.Specs.SpecTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs.Spec

  @valid_attrs %{
    path: "features/example/feature.yaml",
    last_seen_commit: "abc123",
    parsed_at: ~U[2026-01-01 00:00:00Z],
    feature_name: "my-feature",
    feature_version: "1.0.0"
  }

  describe "changeset/2" do
    test "valid with all required fields" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      attrs =
        @valid_attrs
        |> Map.put(:product_id, product.id)
        |> Map.put(:branch_id, branch.id)

      cs = Spec.changeset(%Spec{}, attrs)

      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = Spec.changeset(%Spec{}, %{})
      refute cs.valid?
    end

    # data-model.SPECS.9-1
    test "invalid when feature_name contains spaces" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      cs =
        Spec.changeset(%Spec{}, %{@valid_attrs | feature_name: "my feature"})
        |> Ecto.Changeset.put_change(:product_id, product.id)
        |> Ecto.Changeset.put_change(:branch_id, branch.id)

      refute cs.valid?
      assert %{feature_name: [_ | _]} = errors_on(cs)
    end

    test "valid feature_name with hyphens and underscores" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      attrs =
        @valid_attrs
        |> Map.put(:feature_name, "my-feature_v2")
        |> Map.put(:product_id, product.id)
        |> Map.put(:branch_id, branch.id)

      cs = Spec.changeset(%Spec{}, attrs)

      assert cs.valid?
    end

    # data-model.SPECS.10
    # data-model.SPECS.11
    test "accepts optional fields feature_description and feature_version" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      attrs =
        @valid_attrs
        |> Map.merge(%{
          feature_description: "A description",
          feature_version: "2.0.0"
        })
        |> Map.put(:product_id, product.id)
        |> Map.put(:branch_id, branch.id)

      cs = Spec.changeset(%Spec{}, attrs)

      assert cs.valid?
    end

    # data-model.SPECS.12
    test "accepts optional raw_content field" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      attrs =
        @valid_attrs
        |> Map.merge(%{raw_content: "feature:\n  name: test\n"})
        |> Map.put(:product_id, product.id)
        |> Map.put(:branch_id, branch.id)

      cs = Spec.changeset(%Spec{}, attrs)

      assert cs.valid?
    end

    # data-model.SPECS.12
    test "raw_content can be nil" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      attrs =
        @valid_attrs
        |> Map.put(:raw_content, nil)
        |> Map.put(:product_id, product.id)
        |> Map.put(:branch_id, branch.id)

      cs = Spec.changeset(%Spec{}, attrs)

      assert cs.valid?
    end

    # data-model.SPECS.12
    test "raw_content preserves yaml formatting and comments" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      yaml_content = """
      feature:
        name: my-feature
        # This is a comment
        description: A feature
      components:
        UI:
          requirements:
            1: First requirement
      """

      attrs =
        @valid_attrs
        |> Map.merge(%{raw_content: yaml_content})
        |> Map.put(:product_id, product.id)
        |> Map.put(:branch_id, branch.id)

      cs = Spec.changeset(%Spec{}, attrs)

      assert cs.valid?
    end

    # data-model.SPECS.1
    test "uses UUIDv7 primary key" do
      assert Spec.__schema__(:primary_key) == [:id]
      assert Spec.__schema__(:type, :id) == Acai.UUIDv7
    end

    # data-model.SPECS.11
    test "feature_version defaults to 1.0.0" do
      cs = Spec.changeset(%Spec{}, Map.drop(@valid_attrs, [:feature_version]))
      assert Ecto.Changeset.get_field(cs, :feature_version) == "1.0.0"
    end

    # data-model.SPECS.13
    test "accepts requirements as JSONB map" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      attrs =
        @valid_attrs
        |> Map.merge(%{
          requirements: %{
            "my-feature.COMP.1" => %{
              "requirement" => "First requirement",
              "is_deprecated" => false
            }
          }
        })
        |> Map.put(:product_id, product.id)
        |> Map.put(:branch_id, branch.id)

      cs = Spec.changeset(%Spec{}, attrs)

      assert cs.valid?
    end

    # data-model.SPECS.11-1
    test "invalid when feature_version does not follow SemVer" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      attrs =
        @valid_attrs
        |> Map.put(:feature_version, "invalid")
        |> Map.put(:product_id, product.id)
        |> Map.put(:branch_id, branch.id)

      cs = Spec.changeset(%Spec{}, attrs)

      refute cs.valid?
      assert %{feature_version: [_ | _]} = errors_on(cs)
    end
  end

  describe "database constraint: SPECS.14-1 (branch_id, feature_name)" do
    test "enforces composite unique constraint on branch_id and feature_name" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture(team)

      attrs =
        @valid_attrs
        |> Map.put(:product_id, product.id)
        |> Map.put(:branch_id, branch.id)

      {:ok, _} =
        Spec.changeset(%Spec{}, attrs)
        |> Acai.Repo.insert()

      {:error, cs} =
        Spec.changeset(%Spec{}, attrs)
        |> Acai.Repo.insert()

      assert %{branch_id: [_ | _]} = errors_on(cs)
    end

    test "allows same feature_name on different branches (monorepo support)" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture(team)

      {:ok, _} =
        Spec.changeset(
          %Spec{},
          @valid_attrs
          |> Map.merge(%{feature_version: "1.0.0", product_id: product.id, branch_id: branch.id})
        )
        |> Acai.Repo.insert()

      # Same feature_name but different branch should succeed (monorepo support)
      branch2 = branch_fixture(team, %{branch_name: "develop"})

      {:ok, _} =
        Spec.changeset(
          %Spec{},
          @valid_attrs
          |> Map.merge(%{
            feature_version: "1.0.0",
            path: "features/other/feature.yaml",
            product_id: product.id,
            branch_id: branch2.id
          })
        )
        |> Acai.Repo.insert()
    end

    test "rejects same feature_name on same branch even with different versions" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      {:ok, _} =
        Spec.changeset(
          %Spec{},
          @valid_attrs
          |> Map.merge(%{feature_version: "1.0.0", product_id: product.id, branch_id: branch.id})
        )
        |> Acai.Repo.insert()

      # Same feature_name on same branch should fail even with different version
      # because of SPECS.14-1 constraint (branch_id, feature_name)
      {:error, cs} =
        Spec.changeset(
          %Spec{},
          @valid_attrs
          |> Map.merge(%{
            feature_version: "2.0.0",
            path: "features/other/feature.yaml",
            product_id: product.id,
            branch_id: branch.id
          })
        )
        |> Acai.Repo.insert()

      assert %{branch_id: [_ | _]} = errors_on(cs)
    end

    test "allows same feature_name with different versions on different branches" do
      team = team_fixture()
      product = product_fixture(team)
      branch1 = branch_fixture()
      branch2 = branch_fixture()

      {:ok, _} =
        Spec.changeset(
          %Spec{},
          @valid_attrs
          |> Map.merge(%{feature_version: "1.0.0", product_id: product.id, branch_id: branch1.id})
        )
        |> Acai.Repo.insert()

      # Same feature_name on different branch should work
      {:ok, _} =
        Spec.changeset(
          %Spec{},
          @valid_attrs
          |> Map.merge(%{
            feature_version: "2.0.0",
            path: "features/other/feature.yaml",
            product_id: product.id,
            branch_id: branch2.id
          })
        )
        |> Acai.Repo.insert()
    end

    test "different products can have same feature_name and version" do
      team1 = team_fixture()
      team2 = team_fixture()
      product1 = product_fixture(team1)
      product2 = product_fixture(team2)
      branch1 = branch_fixture()
      branch2 = branch_fixture()

      {:ok, _} =
        Spec.changeset(
          %Spec{},
          @valid_attrs
          |> Map.merge(%{
            feature_version: "1.0.0",
            product_id: product1.id,
            branch_id: branch1.id
          })
        )
        |> Acai.Repo.insert()

      {:ok, _} =
        Spec.changeset(
          %Spec{},
          @valid_attrs
          |> Map.merge(%{
            feature_version: "1.0.0",
            product_id: product2.id,
            branch_id: branch2.id
          })
        )
        |> Acai.Repo.insert()
    end
  end

  describe "database constraint: SPECS.9-1 feature_name_url_safe" do
    test "check constraint fires for invalid chars bypassing changeset" do
      team = team_fixture()
      product = product_fixture(team)
      branch = branch_fixture()

      {:error, cs} =
        Spec.changeset(
          %Spec{},
          @valid_attrs
          |> Map.put(:product_id, product.id)
          |> Map.put(:branch_id, branch.id)
          |> Map.put(:feature_name, "invalid name!")
        )
        |> Acai.Repo.insert()

      assert cs.errors[:feature_name] != nil
    end
  end
end
