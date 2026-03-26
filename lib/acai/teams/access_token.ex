defmodule Acai.Teams.AccessToken do
  use Ecto.Schema
  import Ecto.Changeset

  # data-model.TOKENS.1
  # data-model.FIELDS.2
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "access_tokens" do
    # data-model.TOKENS.2
    belongs_to :user, Acai.Accounts.User, type: :id
    # data-model.TOKENS.10
    belongs_to :team, Acai.Teams.Team

    # data-model.TOKENS.3
    field :name, :string
    # data-model.TOKENS.4
    field :token_hash, :string
    # data-model.TOKENS.5
    field :token_prefix, :string
    # data-model.TOKENS.6
    # data-model.TOKENS.6-1
    field :scopes, {:array, :string},
      default: [
        "specs:read",
        "specs:write",
        "states:read",
        "states:write",
        "refs:read",
        "refs:write",
        "impls:read",
        "impls:write",
        "team:read"
      ]

    # data-model.TOKENS.7
    field :expires_at, :utc_datetime
    # data-model.TOKENS.8
    field :revoked_at, :utc_datetime
    # data-model.TOKENS.9
    field :last_used_at, :utc_datetime

    # Virtual field — not persisted, used transiently when creating a new token
    field :raw_token, :string, virtual: true
    field :expires_at_local, :naive_datetime, virtual: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :token_hash, :token_prefix, :scopes]

  @doc false
  def changeset(token, attrs, timezone_offset \\ 0) do
    token
    |> cast(
      attrs,
      @required_fields ++ [:expires_at, :expires_at_local, :revoked_at, :last_used_at]
    )
    |> validate_required(@required_fields)
    |> compute_expires_at(timezone_offset)
    |> validate_not_expired()
    # data-model.TOKENS.4-1
    |> unique_constraint(:token_hash)
  end

  defp compute_expires_at(changeset, timezone_offset) do
    case get_change(changeset, :expires_at_local) do
      nil ->
        changeset

      local ->
        # JS getTimezoneOffset() is minutes *behind* UTC.
        # So UTC time = local time + offset.
        utc_dt =
          local
          |> DateTime.from_naive!("Etc/UTC")
          |> DateTime.add(timezone_offset, :minute)

        put_change(changeset, :expires_at, utc_dt)
    end
  end

  defp validate_not_expired(changeset) do
    expires_at = get_field(changeset, :expires_at)

    if expires_at && DateTime.compare(DateTime.utc_now(), expires_at) == :gt do
      add_error(changeset, :expires_at_local, "must be in the future")
    else
      changeset
    end
  end
end
