defmodule Acai.Specs.SpecImplRef do
  use Ecto.Schema
  import Ecto.Changeset

  # data-model.SPEC_IMPL_REFS.1
  # data-model.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "spec_impl_refs" do
    # data-model.SPEC_IMPL_REFS.2
    belongs_to :implementation, Acai.Implementations.Implementation
    # data-model.SPEC_IMPL_REFS.3
    belongs_to :spec, Acai.Specs.Spec

    # data-model.SPEC_IMPL_REFS.4
    field :refs, :map, default: %{}
    # data-model.SPEC_IMPL_REFS.5
    field :agent, :string
    # data-model.SPEC_IMPL_REFS.6
    field :commit, :string
    # data-model.SPEC_IMPL_REFS.7
    field :pushed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields [:refs, :agent, :commit, :pushed_at, :implementation_id, :spec_id]
  @optional_fields []

  @doc false
  def changeset(spec_impl_ref, attrs) do
    spec_impl_ref
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.SPEC_IMPL_REFS.8
    |> unique_constraint([:implementation_id, :spec_id])
  end
end
