defmodule Acai.Implementations.Branch do
  @moduledoc """
  Schema for branches.

  ACIDs:
  - data-model.BRANCHES.1: UUIDv7 Primary Key
  - data-model.BRANCHES.2: repo_uri field
  - data-model.BRANCHES.3: branch_name field
  - data-model.BRANCHES.4: last_seen_commit field
  - data-model.BRANCHES.5: Index on (repo_uri)
  - data-model.BRANCHES.6: team_id FK to teams, non-nullable
  - data-model.BRANCHES.6-1: Composite unique constraint on (team_id, repo_uri, branch_name)
  """
  use Ecto.Schema
  import Ecto.Changeset

  # data-model.BRANCHES.1
  # data-model.FIELDS.2
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "branches" do
    # data-model.BRANCHES.6
    belongs_to :team, Acai.Teams.Team

    # data-model.BRANCHES.2
    field :repo_uri, :string
    # data-model.BRANCHES.3
    field :branch_name, :string
    # data-model.BRANCHES.4
    field :last_seen_commit, :string

    # data-model.SPECS.3
    has_many :specs, Acai.Specs.Spec
    # data-model.TRACKED_BRANCHES.2
    has_many :tracked_branches, Acai.Implementations.TrackedBranch
    # data-model.FEATURE_BRANCH_REFS.2
    has_many :feature_branch_refs, Acai.Specs.FeatureBranchRef

    timestamps(type: :utc_datetime)
  end

  @required_fields [:repo_uri, :branch_name, :last_seen_commit, :team_id]

  @doc false
  def changeset(branch, attrs) do
    branch
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    # data-model.BRANCHES.6-1
    |> unique_constraint([:team_id, :repo_uri, :branch_name])
  end
end
