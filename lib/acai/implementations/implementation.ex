defmodule Acai.Implementations.Implementation do
  use Ecto.Schema
  import Ecto.Changeset

  # data-model.IMPLS.1
  # data-model.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "implementations" do
    # data-model.IMPLS.2
    belongs_to :spec, Acai.Specs.Spec
    # data-model.IMPLS.6
    belongs_to :team, Acai.Teams.Team

    # data-model.IMPLS.3
    field :name, :string
    # data-model.IMPLS.4
    field :description, :string
    # data-model.IMPLS.5
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :is_active]
  @optional_fields [:description]

  @doc false
  def changeset(implementation, attrs) do
    implementation
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.IMPLS.7
    |> unique_constraint([:spec_id, :name])
  end
end
