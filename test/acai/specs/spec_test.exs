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

    # data-model.SPECS.9
    # data-model.SPECS.11
    test "accepts optional fields feature_description and feature_version" do
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

    # data-model.SPECS.10
    test "accepts optional raw_content field" do
      cs =
        Spec.changeset(
          %Spec{},
          Map.merge(@valid_attrs, %{
            raw_content: "feature:\n  name: test\n"
          })
        )

      assert cs.valid?
    end

    # data-model.SPECS.10
    test "raw_content can be nil" do
      cs = Spec.changeset(%Spec{}, Map.put(@valid_attrs, :raw_content, nil))
      assert cs.valid?
    end

    # data-model.SPECS.10
    test "raw_content preserves yaml formatting and comments" do
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

      cs = Spec.changeset(%Spec{}, Map.merge(@valid_attrs, %{raw_content: yaml_content}))
      assert cs.valid?
    end

    # data-model.SPECS.1
    test "uses UUIDv7 primary key" do
      assert Spec.__schema__(:primary_key) == [:id]
      assert Spec.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database constraint: SPECS.13 (team_id, repo_uri, branch_name, path)" do
    test "enforces composite unique constraint" do
      team = team_fixture()

      {:ok, _} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      {:error, cs} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      assert %{team_id: [_ | _]} = errors_on(cs)
    end
  end

  describe "database constraint: SPECS.14 (team_id, feature_name, feature_version)" do
    test "rejects duplicate specs with same feature_name and same version" do
      team = team_fixture()

      {:ok, _} =
        Spec.changeset(%Spec{}, Map.merge(@valid_attrs, %{feature_version: "1.0.0"}))
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      {:error, cs} =
        Spec.changeset(
          %Spec{},
          Map.merge(@valid_attrs, %{
            feature_version: "1.0.0",
            branch_name: "develop",
            path: "features/other/feature.yaml"
          })
        )
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      assert %{team_id: [_ | _]} = errors_on(cs)
    end

    test "rejects duplicate specs with same feature_name when both have NULL version" do
      team = team_fixture()

      {:ok, _} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      {:error, cs} =
        Spec.changeset(
          %Spec{},
          Map.merge(@valid_attrs, %{
            branch_name: "develop",
            path: "features/other/feature.yaml"
          })
        )
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      assert %{team_id: [_ | _]} = errors_on(cs)
    end

    test "allows same feature_name with different versions" do
      team = team_fixture()

      {:ok, _} =
        Spec.changeset(%Spec{}, Map.merge(@valid_attrs, %{feature_version: "1.0.0"}))
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      {:ok, _} =
        Spec.changeset(
          %Spec{},
          Map.merge(@valid_attrs, %{
            feature_version: "2.0.0",
            branch_name: "develop",
            path: "features/other/feature.yaml"
          })
        )
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()
    end

    test "allows same feature_name with version vs NULL version" do
      team = team_fixture()

      {:ok, _} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      {:ok, _} =
        Spec.changeset(
          %Spec{},
          Map.merge(@valid_attrs, %{
            feature_version: "1.0.0",
            branch_name: "develop",
            path: "features/other/feature.yaml"
          })
        )
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()
    end

    test "different teams can have same feature_name and version" do
      team1 = team_fixture()
      team2 = team_fixture()

      {:ok, _} =
        Spec.changeset(%Spec{}, Map.merge(@valid_attrs, %{feature_version: "1.0.0"}))
        |> Ecto.Changeset.put_change(:team_id, team1.id)
        |> Acai.Repo.insert()

      {:ok, _} =
        Spec.changeset(%Spec{}, Map.merge(@valid_attrs, %{feature_version: "1.0.0"}))
        |> Ecto.Changeset.put_change(:team_id, team2.id)
        |> Acai.Repo.insert()
    end
  end

  describe "database constraint: SPECS.8-1 feature_name_url_safe" do
    test "check constraint fires for invalid chars bypassing changeset" do
      team = team_fixture()

      {:error, cs} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Ecto.Changeset.put_change(:feature_name, "invalid name!")
        |> Acai.Repo.insert()

      assert cs.errors[:feature_name] != nil
    end
  end

  describe "database constraint: SPECS.12-1 feature_product_url_safe" do
    test "check constraint fires for invalid chars bypassing changeset" do
      team = team_fixture()

      {:error, cs} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Ecto.Changeset.put_change(:feature_product, "invalid product!")
        |> Acai.Repo.insert()

      assert cs.errors[:feature_product] != nil
    end
  end

  describe "database index: SPECS.15 (team_id, feature_name)" do
    test "supports efficient lookup by feature_name within a team" do
      team = team_fixture()
      other_team = team_fixture()

      {:ok, spec1} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      {:ok, _spec2} =
        Spec.changeset(%Spec{}, Map.merge(@valid_attrs, %{feature_name: "other-feature"}))
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Ecto.Changeset.put_change(:branch_name, "develop")
        |> Ecto.Changeset.put_change(:path, "features/other/feature.yaml")
        |> Acai.Repo.insert()

      {:ok, _spec3} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, other_team.id)
        |> Acai.Repo.insert()

      import Ecto.Query

      result =
        Acai.Repo.one(
          from s in Spec,
            where: s.team_id == ^team.id and s.feature_name == ^@valid_attrs.feature_name,
            select: s.id
        )

      assert result == spec1.id
    end
  end
end
