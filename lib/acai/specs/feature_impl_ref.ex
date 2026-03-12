defmodule Acai.Specs.FeatureImplRef do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # data-model.FEATURE_IMPL_REFS.1
  # data-model.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "feature_impl_refs" do
    # data-model.FEATURE_IMPL_REFS.2
    belongs_to :implementation, Acai.Implementations.Implementation

    # data-model.FEATURE_IMPL_REFS.3
    field :feature_name, :string

    # data-model.FEATURE_IMPL_REFS.4
    field :refs, :map, default: %{}
    # data-model.FEATURE_IMPL_REFS.5
    field :agent, :string
    # data-model.FEATURE_IMPL_REFS.6
    field :commit, :string
    # data-model.FEATURE_IMPL_REFS.7
    field :pushed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields [:refs, :agent, :commit, :pushed_at, :implementation_id, :feature_name]
  @optional_fields []

  @doc false
  def changeset(feature_impl_ref, attrs) do
    feature_impl_ref
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.FEATURE_IMPL_REFS.3-1
    |> validate_url_safe(:feature_name)
    |> check_constraint(:feature_name, name: :feature_name_url_safe)
    # data-model.FEATURE_IMPL_REFS.8
    |> unique_constraint([:implementation_id, :feature_name])
  end
end
