defmodule Acai.Specs.Spec do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # data-model.SPECS.1
  # data-model.FIELDS.2
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  # data-model.SPECS.9-1
  @semver_pattern ~r/^\d+\.\d+\.\d+$/

  schema "specs" do
    # data-model.SPECS.3
    belongs_to :branch, Acai.Implementations.Branch
    # data-model.SPECS.2
    belongs_to :product, Acai.Products.Product

    # data-model.SPECS.4
    field :path, :string
    # data-model.SPECS.5
    field :last_seen_commit, :string
    # data-model.SPECS.6
    field :parsed_at, :utc_datetime

    # data-model.SPECS.7
    field :feature_name, :string
    # data-model.SPECS.8
    field :feature_description, :string
    # data-model.SPECS.9
    field :feature_version, :string, default: "1.0.0"
    # data-model.SPECS.10
    field :raw_content, :string
    # data-model.SPECS.11
    field :requirements, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @required_fields [
    :branch_id,
    :last_seen_commit,
    :parsed_at,
    :feature_name,
    :product_id
  ]

  @optional_fields [
    :path,
    :feature_description,
    :feature_version,
    :raw_content,
    # data-model.SPECS.11: Requirements stored as JSONB
    :requirements
  ]

  @doc false
  def changeset(spec, attrs) do
    spec
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.SPECS.7-1
    |> validate_url_safe(:feature_name)
    |> check_constraint(:feature_name, name: :feature_name_url_safe)
    # data-model.SPECS.9-1
    |> validate_format(:feature_version, @semver_pattern,
      message: "must follow SemVer format (e.g., 1.0.0)"
    )
    # data-model.SPECS.12
    |> unique_constraint([:branch_id, :feature_name])
    # data-model.SPECS.15
    |> unique_constraint([:product_id, :feature_name, :feature_version])
  end
end
