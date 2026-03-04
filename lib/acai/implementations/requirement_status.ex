defmodule Acai.Implementations.RequirementStatus do
  use Ecto.Schema
  import Ecto.Changeset

  # DATA.REQ_STATUSES.1
  # DATA.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "requirement_statuses" do
    # DATA.REQ_STATUSES.2
    belongs_to :requirement, Acai.Specs.Requirement
    # DATA.REQ_STATUSES.3
    belongs_to :implementation, Acai.Implementations.Implementation

    # DATA.REQ_STATUSES.4
    field :status, :string
    # DATA.REQ_STATUSES.5
    field :is_active, :boolean, default: true
    # DATA.REQ_STATUSES.6
    field :last_seen_commit, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:is_active, :last_seen_commit]
  @optional_fields [:status]

  @doc false
  def changeset(requirement_status, attrs) do
    requirement_status
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # DATA.REQ_STATUSES.7
    |> unique_constraint([:implementation_id, :requirement_id])
  end
end
