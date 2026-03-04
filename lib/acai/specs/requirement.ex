defmodule Acai.Specs.Requirement do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # DATA.REQS.4
  @group_types [:COMPONENT, :CONSTRAINT]

  # DATA.REQS.1
  # DATA.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "requirements" do
    # DATA.REQS.2
    belongs_to :spec, Acai.Specs.Spec

    # DATA.REQS.3
    # DATA.FIELDS.2
    field :group_key, :string
    # DATA.REQS.4
    field :group_type, Ecto.Enum, values: @group_types
    # DATA.REQS.5
    field :local_id, :string
    # DATA.REQS.6
    field :parent_local_id, :string
    # DATA.REQS.7
    field :definition, :string
    # DATA.REQS.8
    field :note, :string
    # DATA.REQS.9
    field :is_deprecated, :boolean, default: false
    # DATA.REQS.10
    field :replaced_by, {:array, :string}, default: []
    # DATA.REQS.11
    # DATA.FIELDS.2
    field :feature_key, :string

    # DATA.REQS.12 — read-only generated column, never written by the app
    field :acid, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:group_key, :group_type, :local_id, :definition, :is_deprecated, :feature_key]
  @optional_fields [:parent_local_id, :note, :replaced_by]

  @doc false
  def changeset(requirement, attrs) do
    requirement
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # DATA.FIELDS.2
    |> validate_uppercase_key(:group_key)
    # DATA.FIELDS.2
    |> validate_uppercase_key(:feature_key)
    # DATA.REQS.13
    |> unique_constraint([:spec_id, :group_key, :local_id])
  end
end
