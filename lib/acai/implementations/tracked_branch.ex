defmodule Acai.Implementations.TrackedBranch do
  use Ecto.Schema
  import Ecto.Changeset

  # data-model.BRANCHES.1
  # data-model.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "tracked_branches" do
    # data-model.BRANCHES.2
    belongs_to :implementation, Acai.Implementations.Implementation

    # data-model.BRANCHES.3
    field :repo_uri, :string
    # data-model.BRANCHES.4
    field :branch_name, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields [:repo_uri, :branch_name]

  @doc false
  def changeset(tracked_branch, attrs) do
    tracked_branch
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    # data-model.BRANCHES.5
    |> unique_constraint([:implementation_id, :repo_uri])
  end
end
