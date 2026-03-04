defmodule Acai.Implementations.Implementation do
  use Ecto.Schema
  import Ecto.Changeset

  # DATA.IMPLS.1
  # DATA.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "implementations" do
    # DATA.IMPLS.2
    belongs_to :spec, Acai.Specs.Spec
    # DATA.IMPLS.6
    belongs_to :team, Acai.Teams.Team

    # DATA.IMPLS.3
    field :name, :string
    # DATA.IMPLS.4
    field :description, :string
    # DATA.IMPLS.5
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
    # DATA.IMPLS.7
    |> unique_constraint([:spec_id, :name])
  end
end
