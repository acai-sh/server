defmodule Acai.Implementations.TrackedBranch do
  use Ecto.Schema
  import Ecto.Changeset

  # data-model.TRACKED_BRANCHES.3
  @primary_key false
  @foreign_key_type Acai.UUIDv7

  schema "tracked_branches" do
    # data-model.TRACKED_BRANCHES.1
    belongs_to :implementation, Acai.Implementations.Implementation, primary_key: true

    # data-model.TRACKED_BRANCHES.2
    belongs_to :branch, Acai.Implementations.Branch, primary_key: true

    # data-model.TRACKED_BRANCHES.5
    field :repo_uri, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:implementation_id, :branch_id, :repo_uri]

  @doc false
  def changeset(tracked_branch, attrs) do
    tracked_branch
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    # data-model.TRACKED_BRANCHES.4
    |> unique_constraint([:implementation_id, :repo_uri])
  end
end
