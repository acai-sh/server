defmodule Acai.Specs.RequirementTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Specs.Requirement

  @valid_attrs %{
    group_key: "COMP",
    group_type: :COMPONENT,
    local_id: "1",
    definition: "The system must do something.",
    is_deprecated: false,
    feature_key: "MYFEAT",
    replaced_by: []
  }

  describe "changeset/2" do
    test "valid with required fields" do
      cs = Requirement.changeset(%Requirement{}, @valid_attrs)
      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = Requirement.changeset(%Requirement{}, %{})
      refute cs.valid?
    end

    # DATA.REQS.4
    test "invalid group_type is rejected" do
      cs = Requirement.changeset(%Requirement{}, %{@valid_attrs | group_type: :UNKNOWN})
      refute cs.valid?
    end

    test "accepts CONSTRAINT group_type" do
      cs = Requirement.changeset(%Requirement{}, %{@valid_attrs | group_type: :CONSTRAINT})
      assert cs.valid?
    end

    # DATA.FIELDS.2
    test "invalid when group_key is lowercase" do
      cs = Requirement.changeset(%Requirement{}, %{@valid_attrs | group_key: "comp"})
      refute cs.valid?
      assert %{group_key: [_ | _]} = errors_on(cs)
    end

    # DATA.FIELDS.2
    test "invalid when feature_key is lowercase" do
      cs = Requirement.changeset(%Requirement{}, %{@valid_attrs | feature_key: "myfeat"})
      refute cs.valid?
      assert %{feature_key: [_ | _]} = errors_on(cs)
    end

    # DATA.REQS.6
    # DATA.REQS.8
    test "accepts optional fields" do
      cs =
        Requirement.changeset(
          %Requirement{},
          Map.merge(@valid_attrs, %{
            parent_local_id: "1",
            note: "See also X.",
            replaced_by: ["OTHER.COMP.2"]
          })
        )

      assert cs.valid?
    end

    # DATA.REQS.1
    test "uses UUIDv7 primary key" do
      assert Requirement.__schema__(:primary_key) == [:id]
      assert Requirement.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database constraints" do
    # DATA.REQS.12
    test "acid generated column is populated on insert" do
      team = team_fixture()
      spec = spec_fixture(team)
      req = requirement_fixture(spec, %{feature_key: "DATA", group_key: "REQS", local_id: "1"})
      # reload to pick up the GENERATED ALWAYS AS column value from Postgres
      req = Acai.Repo.reload!(req)
      assert req.acid == "DATA.REQS.1"
    end

    # DATA.REQS.13
    test "composite unique constraint on (spec_id, group_key, local_id)" do
      team = team_fixture()
      spec = spec_fixture(team)
      requirement_fixture(spec, %{group_key: "COMP", local_id: "1"})

      {:error, cs} =
        Requirement.changeset(%Requirement{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:spec_id, spec.id)
        |> Acai.Repo.insert()

      assert %{spec_id: [_ | _]} = errors_on(cs)
    end
  end
end
