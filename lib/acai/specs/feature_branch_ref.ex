defmodule Acai.Specs.FeatureBranchRef do
  @moduledoc """
  Schema for branch-scoped feature references.

  Stores code references for a feature on a specific branch.
  References are aggregated from tracked branches for implementations.

  ACIDs:
  - data-model.FEATURE_BRANCH_REFS.1: UUIDv7 Primary Key
  - data-model.FEATURE_BRANCH_REFS.2: branch_id FK to branches
  - data-model.FEATURE_BRANCH_REFS.3: feature_name matching spec.feature_name
  - data-model.FEATURE_BRANCH_REFS.3-1: feature_name must be URL-safe
  - data-model.FEATURE_BRANCH_REFS.4: refs JSONB column
  - data-model.FEATURE_BRANCH_REFS.4-1: refs keyed by full ACID string
  - data-model.FEATURE_BRANCH_REFS.4-2: Each ACID has array of reference objects
  - data-model.FEATURE_BRANCH_REFS.4-3: Reference objects contain path, is_test
  - data-model.FEATURE_BRANCH_REFS.5: commit hash string
  - data-model.FEATURE_BRANCH_REFS.6: pushed_at timestamp
  - data-model.FEATURE_BRANCH_REFS.7: Unique constraint on (branch_id, feature_name)
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # data-model.FEATURE_BRANCH_REFS.1
  # data-model.FIELDS.2
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "feature_branch_refs" do
    # data-model.FEATURE_BRANCH_REFS.2
    belongs_to :branch, Acai.Implementations.Branch

    # data-model.FEATURE_BRANCH_REFS.3
    field :feature_name, :string

    # data-model.FEATURE_BRANCH_REFS.4
    # Format: %{"acid" => [%{"path" => "lib/foo.ex:42", "is_test" => false}, ...]}
    field :refs, :map, default: %{}

    # data-model.FEATURE_BRANCH_REFS.5
    field :commit, :string
    # data-model.FEATURE_BRANCH_REFS.6
    field :pushed_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields [:refs, :commit, :pushed_at, :branch_id, :feature_name]
  @optional_fields []

  @doc false
  def changeset(feature_branch_ref, attrs) do
    feature_branch_ref
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.FEATURE_BRANCH_REFS.3-1
    |> validate_url_safe(:feature_name)
    |> check_constraint(:feature_name, name: :feature_name_url_safe)
    # data-model.FEATURE_BRANCH_REFS.7
    |> unique_constraint([:branch_id, :feature_name])
  end
end
