defmodule Acai.Teams.AccessToken do
  use Ecto.Schema
  import Ecto.Changeset

  # DATA.TOKENS.1
  # DATA.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "access_tokens" do
    # DATA.TOKENS.2
    belongs_to :user, Acai.Accounts.User, type: :id
    # DATA.TOKENS.10
    belongs_to :team, Acai.Teams.Team

    # DATA.TOKENS.3
    field :name, :string
    # DATA.TOKENS.4
    field :token_hash, :string
    # DATA.TOKENS.5
    field :token_prefix, :string
    # DATA.TOKENS.6
    # DATA.TOKENS.6-1
    field :scopes, {:array, :string},
      default: [
        "specs:read",
        "specs:write",
        "refs:read",
        "refs:write",
        "impls:read",
        "impls:write",
        "team:read"
      ]

    # DATA.TOKENS.7
    field :expires_at, :utc_datetime
    # DATA.TOKENS.8
    field :revoked_at, :utc_datetime
    # DATA.TOKENS.9
    field :last_used_at, :utc_datetime

    # Virtual field — not persisted, used transiently when creating a new token
    field :raw_token, :string, virtual: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :token_hash, :token_prefix, :scopes]

  @doc false
  def changeset(token, attrs) do
    token
    |> cast(attrs, @required_fields ++ [:expires_at, :revoked_at, :last_used_at])
    |> validate_required(@required_fields)
    # DATA.TOKENS.4-1
    |> unique_constraint(:token_hash)
  end
end
