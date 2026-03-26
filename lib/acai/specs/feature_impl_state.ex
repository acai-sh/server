defmodule Acai.Specs.FeatureImplState do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # data-model.FEATURE_IMPL_STATES.1
  # data-model.FIELDS.2
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "feature_impl_states" do
    # data-model.FEATURE_IMPL_STATES.2
    belongs_to :implementation, Acai.Implementations.Implementation

    # data-model.FEATURE_IMPL_STATES.3
    field :feature_name, :string

    # data-model.FEATURE_IMPL_STATES.4
    field :states, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @required_fields [:states, :implementation_id, :feature_name]
  @optional_fields []

  @doc false
  def changeset(feature_impl_state, attrs) do
    feature_impl_state
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.FEATURE_IMPL_STATES.3-1
    |> validate_url_safe(:feature_name)
    |> check_constraint(:feature_name, name: :feature_name_url_safe)
    # data-model.FEATURE_IMPL_STATES.5
    |> unique_constraint([:implementation_id, :feature_name])
  end
end
