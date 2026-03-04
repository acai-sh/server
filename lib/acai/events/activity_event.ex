defmodule Acai.Events.ActivityEvent do
  use Ecto.Schema
  import Ecto.Changeset

  # DATA.EVENTS.1
  # DATA.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  # DATA.EVENTS.9 — append-only, no updated_at
  @timestamps_opts [type: :utc_datetime, inserted_at: :created_at, updated_at: false]

  schema "activity_events" do
    # DATA.EVENTS.2
    belongs_to :team, Acai.Teams.Team
    # DATA.EVENTS.3
    belongs_to :actor_token, Acai.Teams.AccessToken, foreign_key: :actor_token_id

    # DATA.EVENTS.4
    field :event_type, :string
    # DATA.EVENTS.5
    field :subject_type, :string
    # DATA.EVENTS.6
    field :subject_id, Acai.UUIDv7
    # DATA.EVENTS.7
    field :batch_id, Acai.UUIDv7
    # DATA.EVENTS.8
    field :payload, :map, default: %{}

    # DATA.EVENTS.9
    timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
  end

  @required_fields [:event_type, :subject_type, :subject_id, :payload]
  @optional_fields [:actor_token_id, :batch_id]

  @doc false
  def changeset(activity_event, attrs) do
    activity_event
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
