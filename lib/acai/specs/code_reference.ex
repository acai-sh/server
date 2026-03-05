defmodule Acai.Specs.CodeReference do
  use Ecto.Schema
  import Ecto.Changeset

  # data-model.REFS.1
  # data-model.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "code_references" do
    # data-model.REFS.2
    belongs_to :requirement, Acai.Specs.Requirement

    # data-model.REFS.10
    belongs_to :branch, Acai.Implementations.TrackedBranch

    # data-model.REFS.3
    field :repo_uri, :string
    # data-model.REFS.5
    field :last_seen_commit, :string
    # data-model.REFS.6
    field :acid_string, :string
    # data-model.REFS.7
    field :last_seen_at, :utc_datetime
    # data-model.REFS.8
    field :path, :string
    # data-model.REFS.9
    field :is_test, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @required_fields [:repo_uri, :last_seen_commit, :acid_string, :path, :is_test]
  @optional_fields [:last_seen_at]

  @doc false
  def changeset(code_reference, attrs) do
    code_reference
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.REFS unique constraint (requirement_id, branch_id, path)
    |> unique_constraint([:requirement_id, :branch_id, :path])
  end
end
