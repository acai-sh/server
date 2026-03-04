defmodule Acai.Specs.SpecTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs.Spec

  @valid_attrs %{
    repo_uri: "github.com/acai-sh/server",
    branch_name: "main",
    path: "features/example/feature.yaml",
    last_seen_commit: "abc123",
    parsed_at: ~U[2026-01-01 00:00:00Z],
    feature_name: "my-feature",
    feature_product: "acai"
  }

  describe "changeset/2" do
    test "valid with all required fields" do
      cs = Spec.changeset(%Spec{}, @valid_attrs)
      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = Spec.changeset(%Spec{}, %{})
      refute cs.valid?
    end

    # data-model.SPECS.8-1
    test "invalid when feature_name contains spaces" do
      cs = Spec.changeset(%Spec{}, %{@valid_attrs | feature_name: "my feature"})
      refute cs.valid?
      assert %{feature_name: [_ | _]} = errors_on(cs)
    end

    test "valid feature_name with hyphens and underscores" do
      cs = Spec.changeset(%Spec{}, %{@valid_attrs | feature_name: "my-feature_v2"})
      assert cs.valid?
    end

    # data-model.SPECS.12-1
    test "invalid when feature_product contains spaces" do
      cs = Spec.changeset(%Spec{}, %{@valid_attrs | feature_product: "my product"})
      refute cs.valid?
      assert %{feature_product: [_ | _]} = errors_on(cs)
    end

    # data-model.SPECS.10
    # data-model.SPECS.11
    test "accepts optional fields" do
      cs =
        Spec.changeset(
          %Spec{},
          Map.merge(@valid_attrs, %{
            feature_description: "A description",
            feature_version: "1.0.0"
          })
        )

      assert cs.valid?
    end

    # data-model.SPECS.1
    test "uses UUIDv7 primary key" do
      assert Spec.__schema__(:primary_key) == [:id]
      assert Spec.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database constraints" do
    # data-model.SPECS.13
    test "composite unique constraint on (team_id, repo_uri, branch_name, path)" do
      team = team_fixture()
      spec_fixture(team)

      {:error, cs} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      assert %{team_id: [_ | _]} = errors_on(cs)
    end

    # data-model.SPECS.8-1
    test "feature_name_url_safe check constraint fires for invalid chars bypassing changeset" do
      team = team_fixture()

      {:error, cs} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Ecto.Changeset.put_change(:feature_name, "invalid name!")
        |> Acai.Repo.insert()

      assert cs.errors[:feature_name] != nil
    end

    # data-model.SPECS.12-1
    test "feature_product_url_safe check constraint fires for invalid chars bypassing changeset" do
      team = team_fixture()

      {:error, cs} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Ecto.Changeset.put_change(:feature_product, "invalid product!")
        |> Acai.Repo.insert()

      assert cs.errors[:feature_product] != nil
    end
  end
end
