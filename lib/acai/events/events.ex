defmodule Acai.Events do
  @moduledoc """
  Context for activity events (append-only log).
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Events.ActivityEvent
  alias Acai.Teams.Team

  # --- Activity Events ---

  def list_team_events(_current_scope, %Team{} = team) do
    # data-model.EVENTS_IDX.1
    Repo.all(
      from e in ActivityEvent,
        where: e.team_id == ^team.id,
        order_by: [desc: e.created_at]
    )
  end

  def list_subject_events(subject_type, subject_id) do
    # data-model.EVENTS_IDX.2
    Repo.all(
      from e in ActivityEvent,
        where: e.subject_type == ^subject_type and e.subject_id == ^subject_id,
        order_by: [desc: e.created_at]
    )
  end

  def list_batch_events(batch_id) do
    # data-model.EVENTS_IDX.3
    Repo.all(from e in ActivityEvent, where: e.batch_id == ^batch_id)
  end

  def create_activity_event(%Team{} = team, attrs) do
    %ActivityEvent{}
    |> ActivityEvent.changeset(attrs)
    |> Ecto.Changeset.put_change(:team_id, team.id)
    |> Repo.insert()
  end

  def change_activity_event(%ActivityEvent{} = activity_event, attrs \\ %{}) do
    ActivityEvent.changeset(activity_event, attrs)
  end
end
