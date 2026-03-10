defmodule Acai.Specs.SpecImplState do
  use Ecto.Schema
  import Ecto.Changeset

  # data-model.SPEC_IMPL_STATES.1
  # data-model.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "spec_impl_states" do
    # data-model.SPEC_IMPL_STATES.2
    belongs_to :implementation, Acai.Implementations.Implementation
    # data-model.SPEC_IMPL_STATES.3
    belongs_to :spec, Acai.Specs.Spec

    # data-model.SPEC_IMPL_STATES.4
    field :states, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @required_fields [:states, :implementation_id, :spec_id]
  @optional_fields []

  @doc false
  def changeset(spec_impl_state, attrs) do
    spec_impl_state
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.SPEC_IMPL_STATES.5
    |> unique_constraint([:implementation_id, :spec_id])
  end
end
