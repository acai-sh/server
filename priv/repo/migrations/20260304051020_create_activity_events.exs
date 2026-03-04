defmodule Acai.Repo.Migrations.CreateActivityEvents do
  use Ecto.Migration

  def change do
    # data-model.EVENTS.1
    create table(:activity_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # data-model.EVENTS.2
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      # data-model.EVENTS.3
      add :actor_token_id, references(:access_tokens, type: :uuid, on_delete: :delete_all)

      # data-model.EVENTS.4
      add :event_type, :string, null: false
      # data-model.EVENTS.5
      add :subject_type, :string, null: false
      # data-model.EVENTS.6
      add :subject_id, :uuid, null: false
      # data-model.EVENTS.7
      add :batch_id, :uuid
      # data-model.EVENTS.8
      add :payload, :jsonb, null: false, default: "{}"

      # data-model.EVENTS.9
      # data-model.FIELDS.1
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    # data-model.EVENTS_IDX.1
    create index(:activity_events, [:team_id, :created_at])

    # data-model.EVENTS_IDX.2
    create index(:activity_events, [:subject_type, :subject_id, :created_at])

    # data-model.EVENTS_IDX.3
    create index(:activity_events, [:batch_id])
  end
end
