defmodule Acai.Specs.CodeReference do
  use Ecto.Schema
  import Ecto.Changeset

  # DATA.REFS.1
  # DATA.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "code_references" do
    # DATA.REFS.2
    belongs_to :requirement, Acai.Specs.Requirement

    # DATA.REFS.3
    field :repo_uri, :string
    # DATA.REFS.4
    field :branch_name, :string
    # DATA.REFS.5
    field :last_seen_commit, :string
    # DATA.REFS.6
    field :acid_string, :string
    # DATA.REFS.7
    field :last_seen_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  @required_fields [:repo_uri, :branch_name, :last_seen_commit, :acid_string]
  @optional_fields [:last_seen_at]

  @doc false
  def changeset(code_reference, attrs) do
    code_reference
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
  end
end
