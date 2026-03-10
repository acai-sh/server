defmodule Acai.Specs.Spec do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # data-model.SPECS.1
  # data-model.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  # data-model.SPECS.11-1
  @semver_pattern ~r/^\d+\.\d+\.\d+$/

  schema "specs" do
    # data-model.SPECS.2
    belongs_to :team, Acai.Teams.Team
    # data-model.SPECS.3
    belongs_to :tracked_branch, Acai.Implementations.TrackedBranch
    # data-model.SPECS.14
    belongs_to :product, Acai.Products.Product

    # data-model.SPECS.4
    field :repo_uri, :string
    # data-model.SPECS.5
    field :branch_name, :string
    # data-model.SPECS.6
    field :path, :string
    # data-model.SPECS.7
    field :last_seen_commit, :string
    # data-model.SPECS.8
    field :parsed_at, :utc_datetime

    # data-model.SPECS.9
    field :feature_name, :string
    # data-model.SPECS.10
    field :feature_description, :string
    # data-model.SPECS.11
    field :feature_version, :string, default: "1.0.0"
    # data-model.SPECS.12
    field :raw_content, :string
    # data-model.SPECS.13
    field :requirements, :map, default: %{}

    timestamps(type: :utc_datetime)
  end

  @required_fields [
    :repo_uri,
    :branch_name,
    :last_seen_commit,
    :parsed_at,
    :feature_name,
    :product_id,
    :team_id
  ]

  @optional_fields [
    :path,
    :feature_description,
    :feature_version,
    :raw_content,
    :tracked_branch_id
  ]

  @doc false
  def changeset(spec, attrs) do
    spec
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.SPECS.9-1
    |> validate_url_safe(:feature_name)
    |> check_constraint(:feature_name, name: :feature_name_url_safe)
    # data-model.SPECS.11-1
    |> validate_format(:feature_version, @semver_pattern,
      message: "must follow SemVer format (e.g., 1.0.0)"
    )
    # data-model.SPECS.15
    |> unique_constraint([:team_id, :repo_uri, :branch_name, :feature_name])
    # data-model.SPECS.16
    |> unique_constraint([:team_id, :feature_name, :feature_version],
      name: :specs_team_feature_version_unique_idx
    )
  end
end
