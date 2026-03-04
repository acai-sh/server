defmodule Acai.Implementations.RequirementStatusTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Implementations.RequirementStatus

  @valid_attrs %{is_active: true, last_seen_commit: "abc123"}

  describe "changeset/2" do
    test "valid with required fields" do
      cs = RequirementStatus.changeset(%RequirementStatus{}, @valid_attrs)
      assert cs.valid?
    end

    # data-model.REQ_STATUSES.6
    test "invalid without last_seen_commit" do
      cs = RequirementStatus.changeset(%RequirementStatus{}, %{is_active: true})
      refute cs.valid?
      assert %{last_seen_commit: [_ | _]} = errors_on(cs)
    end

    # data-model.REQ_STATUSES.4
    test "accepts optional status" do
      cs =
        RequirementStatus.changeset(
          %RequirementStatus{},
          Map.put(@valid_attrs, :status, "passing")
        )

      assert cs.valid?
    end

    # data-model.REQ_STATUSES.1
    test "uses UUIDv7 primary key" do
      assert RequirementStatus.__schema__(:primary_key) == [:id]
      assert RequirementStatus.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database constraints" do
    # data-model.REQ_STATUSES.7
    test "composite unique constraint on (implementation_id, requirement_id)" do
      team = team_fixture()
      spec = spec_fixture(team)
      req = requirement_fixture(spec)
      impl = implementation_fixture(spec)
      requirement_status_fixture(impl, req)

      {:error, cs} =
        RequirementStatus.changeset(%RequirementStatus{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:implementation_id, impl.id)
        |> Ecto.Changeset.put_change(:requirement_id, req.id)
        |> Acai.Repo.insert()

      assert %{implementation_id: [_ | _]} = errors_on(cs)
    end
  end
end
