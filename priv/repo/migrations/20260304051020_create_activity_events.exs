defmodule Acai.Repo.Migrations.CreateActivityEvents do
  use Ecto.Migration

  def change do
    # DATA.EVENTS.1
    create table(:activity_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # DATA.EVENTS.2
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      # DATA.EVENTS.3
      add :actor_token_id, references(:access_tokens, type: :uuid, on_delete: :delete_all)

      # DATA.EVENTS.4
      add :event_type, :string, null: false
      # DATA.EVENTS.5
      add :subject_type, :string, null: false
      # DATA.EVENTS.6
      add :subject_id, :uuid, null: false
      # DATA.EVENTS.7
      add :batch_id, :uuid
      # DATA.EVENTS.8
      add :payload, :jsonb, null: false, default: "{}"

      # DATA.EVENTS.9
      # DATA.FIELDS.1
      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    # DATA.EVENTS_IDX.1
    create index(:activity_events, [:team_id, :created_at])

    # DATA.EVENTS_IDX.2
    create index(:activity_events, [:subject_type, :subject_id, :created_at])

    # DATA.EVENTS_IDX.3
    create index(:activity_events, [:batch_id])
  end
end
