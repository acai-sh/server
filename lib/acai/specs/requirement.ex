defmodule Acai.Specs.Requirement do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # data-model.REQS.4
  @group_types [:COMPONENT, :CONSTRAINT]

  # data-model.REQS.1
  # data-model.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "requirements" do
    # data-model.REQS.2
    belongs_to :spec, Acai.Specs.Spec

    # data-model.REQS.3
    # data-model.FIELDS.2
    field :group_key, :string
    # data-model.REQS.4
    field :group_type, Ecto.Enum, values: @group_types
    # data-model.REQS.5
    field :local_id, :string
    # data-model.REQS.6
    field :parent_local_id, :string
    # data-model.REQS.7
    field :definition, :string
    # data-model.REQS.8
    field :note, :string
    # data-model.REQS.9
    field :is_deprecated, :boolean, default: false
    # data-model.REQS.10
    field :replaced_by, {:array, :string}, default: []
    # data-model.REQS.11
    # data-model.FIELDS.2
    field :feature_name, :string

    # data-model.REQS.12 — read-only generated column, never written by the app
    field :acid, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [
    :group_key,
    :group_type,
    :local_id,
    :definition,
    :is_deprecated,
    :feature_name
  ]
  @optional_fields [:parent_local_id, :note, :replaced_by]

  @doc false
  def changeset(requirement, attrs) do
    requirement
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.FIELDS.2
    |> validate_uppercase_key(:group_key)
    # data-model.FIELDS.2
    |> validate_url_safe(:feature_name)
    # data-model.REQS.13
    |> unique_constraint([:spec_id, :group_key, :local_id])
  end
end
