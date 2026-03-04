defmodule Acai.Events.ActivityEventTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures

  alias Acai.Events.ActivityEvent

  @valid_attrs %{
    event_type: "spec.created",
    subject_type: "spec",
    subject_id: "018e1234-5678-7000-8000-000000000001",
    payload: %{"key" => "value"}
  }

  describe "changeset/2" do
    test "valid with required fields" do
      cs = ActivityEvent.changeset(%ActivityEvent{}, @valid_attrs)
      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = ActivityEvent.changeset(%ActivityEvent{}, %{})
      refute cs.valid?
    end

    # data-model.EVENTS.4
    test "invalid without event_type" do
      cs = ActivityEvent.changeset(%ActivityEvent{}, Map.delete(@valid_attrs, :event_type))
      refute cs.valid?
      assert %{event_type: [_ | _]} = errors_on(cs)
    end

    # data-model.EVENTS.5
    test "invalid without subject_type" do
      cs = ActivityEvent.changeset(%ActivityEvent{}, Map.delete(@valid_attrs, :subject_type))
      refute cs.valid?
    end

    # data-model.EVENTS.6
    test "invalid without subject_id" do
      cs = ActivityEvent.changeset(%ActivityEvent{}, Map.delete(@valid_attrs, :subject_id))
      refute cs.valid?
    end

    # data-model.EVENTS.7
    test "accepts optional batch_id" do
      cs =
        ActivityEvent.changeset(
          %ActivityEvent{},
          Map.put(@valid_attrs, :batch_id, Acai.UUIDv7.autogenerate())
        )

      assert cs.valid?
    end

    # data-model.EVENTS.1
    test "uses UUIDv7 primary key" do
      assert ActivityEvent.__schema__(:primary_key) == [:id]
      assert ActivityEvent.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database - append-only" do
    # data-model.EVENTS.9
    test "created_at is set on insert and updated_at does not exist" do
      team = team_fixture()
      event = activity_event_fixture(team)

      assert event.created_at != nil
      refute Map.has_key?(event, :updated_at)
    end
  end

  describe "database - data-model.EVENTS.3 actor_token_id nilify on delete" do
    test "deleting the actor token nullifies actor_token_id rather than deleting the event" do
      import Acai.AccountsFixtures

      team = team_fixture()
      user = user_fixture()
      token = access_token_fixture(team, user)

      {:ok, event} =
        ActivityEvent.changeset(%ActivityEvent{}, @valid_attrs)
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Ecto.Changeset.put_change(:actor_token_id, token.id)
        |> Acai.Repo.insert()

      Acai.Repo.delete!(token)

      reloaded = Acai.Repo.get!(ActivityEvent, event.id)
      assert reloaded.actor_token_id == nil
    end
  end
end
