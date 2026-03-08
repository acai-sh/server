defmodule Acai.Specs.Spec do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # data-model.SPECS.1
  # data-model.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "specs" do
    # data-model.SPECS.7
    belongs_to :team, Acai.Teams.Team

    # data-model.SPECS.2
    field :repo_uri, :string
    # data-model.SPECS.3
    field :branch_name, :string
    # data-model.SPECS.4
    field :path, :string
    # data-model.SPECS.5
    field :last_seen_commit, :string
    # data-model.SPECS.6
    field :parsed_at, :utc_datetime

    # data-model.SPECS.8
    # data-model.SPECS.8-1
    field :feature_name, :string
    # data-model.SPECS.9
    field :feature_description, :string
    # data-model.SPECS.10
    field :raw_content, :string
    # data-model.SPECS.11
    field :feature_version, :string
    # data-model.SPECS.12
    # data-model.SPECS.12-1
    field :feature_product, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [
    :repo_uri,
    :branch_name,
    :path,
    :last_seen_commit,
    :parsed_at,
    :feature_name,
    :feature_product
  ]

  @optional_fields [:feature_description, :feature_version, :raw_content]

  @doc false
  def changeset(spec, attrs) do
    spec
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.SPECS.8-1
    |> validate_url_safe(:feature_name)
    |> check_constraint(:feature_name, name: :feature_name_url_safe)
    # data-model.SPECS.12-1
    |> validate_url_safe(:feature_product)
    |> check_constraint(:feature_product, name: :feature_product_url_safe)
    # data-model.SPECS.13
    |> unique_constraint([:team_id, :repo_uri, :branch_name, :path])
    # data-model.SPECS.14
    |> unique_constraint([:team_id, :feature_name, :feature_version],
      name: :specs_team_feature_version_unique_idx
    )
  end
end
