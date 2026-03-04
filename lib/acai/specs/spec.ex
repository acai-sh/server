defmodule Acai.Specs.Spec do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # DATA.SPECS.1
  # DATA.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "specs" do
    # DATA.SPECS.7
    belongs_to :team, Acai.Teams.Team

    # DATA.SPECS.2
    field :repo_uri, :string
    # DATA.SPECS.3
    field :branch_name, :string
    # DATA.SPECS.4
    field :path, :string
    # DATA.SPECS.5
    field :last_seen_commit, :string
    # DATA.SPECS.6
    field :parsed_at, :utc_datetime

    # DATA.SPECS.8
    # DATA.SPECS.8-1
    field :feature_name, :string
    # DATA.SPECS.9
    # DATA.FIELDS.2
    field :feature_key, :string
    # DATA.SPECS.10
    field :feature_description, :string
    # DATA.SPECS.11
    field :feature_version, :string
    # DATA.SPECS.12
    # DATA.SPECS.12-1
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
    :feature_key,
    :feature_product
  ]

  @optional_fields [:feature_description, :feature_version]

  @doc false
  def changeset(spec, attrs) do
    spec
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # DATA.SPECS.8-1
    |> validate_url_safe(:feature_name)
    # DATA.FIELDS.2
    |> validate_uppercase_key(:feature_key)
    # DATA.SPECS.12-1
    |> validate_url_safe(:feature_product)
    # DATA.SPECS.13
    |> unique_constraint([:team_id, :repo_uri, :branch_name, :path])
  end
end
