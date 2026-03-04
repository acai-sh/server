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
    feature_key: "MYFEAT",
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

    # DATA.SPECS.8-1
    test "invalid when feature_name contains spaces" do
      cs = Spec.changeset(%Spec{}, %{@valid_attrs | feature_name: "my feature"})
      refute cs.valid?
      assert %{feature_name: [_ | _]} = errors_on(cs)
    end

    test "valid feature_name with hyphens and underscores" do
      cs = Spec.changeset(%Spec{}, %{@valid_attrs | feature_name: "my-feature_v2"})
      assert cs.valid?
    end

    # DATA.FIELDS.2
    test "invalid when feature_key is lowercase" do
      cs = Spec.changeset(%Spec{}, %{@valid_attrs | feature_key: "myfeat"})
      refute cs.valid?
      assert %{feature_key: [_ | _]} = errors_on(cs)
    end

    test "valid feature_key with uppercase and underscores" do
      cs = Spec.changeset(%Spec{}, %{@valid_attrs | feature_key: "MY_FEAT"})
      assert cs.valid?
    end

    # DATA.SPECS.12-1
    test "invalid when feature_product contains spaces" do
      cs = Spec.changeset(%Spec{}, %{@valid_attrs | feature_product: "my product"})
      refute cs.valid?
      assert %{feature_product: [_ | _]} = errors_on(cs)
    end

    # DATA.SPECS.10
    # DATA.SPECS.11
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

    # DATA.SPECS.1
    test "uses UUIDv7 primary key" do
      assert Spec.__schema__(:primary_key) == [:id]
      assert Spec.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database constraints" do
    # DATA.SPECS.13
    test "composite unique constraint on (team_id, repo_uri, branch_name, path)" do
      team = team_fixture()
      spec_fixture(team)

      {:error, cs} =
        Spec.changeset(%Spec{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Acai.Repo.insert()

      assert %{team_id: [_ | _]} = errors_on(cs)
    end
  end
end
