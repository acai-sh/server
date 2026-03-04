defmodule Acai.Repo.Migrations.CreateAccessTokens do
  use Ecto.Migration

  def change do
    # data-model.TOKENS.1
    create table(:access_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # data-model.TOKENS.2
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # data-model.TOKENS.10
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false

      # data-model.TOKENS.3
      add :name, :string, null: false
      # data-model.TOKENS.4
      add :token_hash, :string, null: false
      # data-model.TOKENS.5
      add :token_prefix, :string, null: false
      # data-model.TOKENS.6
      add :scopes, :jsonb, null: false, default: "[]"

      # data-model.TOKENS.7
      add :expires_at, :utc_datetime
      # data-model.TOKENS.8
      add :revoked_at, :utc_datetime
      # data-model.TOKENS.9
      add :last_used_at, :utc_datetime

      # data-model.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # data-model.TOKENS.4-1
    create unique_index(:access_tokens, [:token_hash])
  end
end
