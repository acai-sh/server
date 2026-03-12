defmodule Acai.Implementations.Branch do
  use Ecto.Schema
  import Ecto.Changeset

  # data-model.BRANCHES.1
  # data-model.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "branches" do
    # data-model.BRANCHES.3
    field :repo_uri, :string
    # data-model.BRANCHES.4
    field :branch_name, :string
    # data-model.BRANCHES.5
    field :last_seen_commit, :string

    # data-model.SPECS.3-1
    has_many :specs, Acai.Specs.Spec
    # data-model.TRACKED_BRANCHES.2
    has_many :tracked_branches, Acai.Implementations.TrackedBranch

    timestamps(type: :utc_datetime)
  end

  @required_fields [:repo_uri, :branch_name, :last_seen_commit]

  @doc false
  def changeset(branch, attrs) do
    branch
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    # data-model.BRANCHES.8
    |> unique_constraint([:repo_uri, :branch_name])
  end
end
