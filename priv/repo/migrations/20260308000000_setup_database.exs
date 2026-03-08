defmodule Acai.Repo.Migrations.SetupDatabase do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    create table(:users) do
      add :email, :citext, null: false
      add :hashed_password, :string
      add :confirmed_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:users, [:email])

    create table(:users_tokens) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :token, :binary, null: false
      add :context, :string, null: false
      add :sent_to, :string
      add :authenticated_at, :utc_datetime

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:users_tokens, [:user_id])
    create unique_index(:users_tokens, [:context, :token])

    create table(:teams, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :name, :citext, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:teams, [:name])
    create constraint(:teams, :name_url_safe, check: "name ~ '^[a-zA-Z0-9_-]+$'")

    create table(:user_team_roles, primary_key: false) do
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :title, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:user_team_roles, [:team_id, :user_id])

    create table(:access_tokens, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :token_hash, :string, null: false
      add :token_prefix, :string, null: false

      add :scopes, :jsonb,
        null: false,
        default:
          fragment(
            "'[\"specs:read\",\"specs:write\",\"refs:read\",\"refs:write\",\"impls:read\",\"impls:write\",\"team:read\"]'::jsonb"
          )

      add :expires_at, :utc_datetime
      add :revoked_at, :utc_datetime
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create unique_index(:access_tokens, [:token_hash])

    create table(:specs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      add :repo_uri, :text, null: false
      add :branch_name, :string, null: false
      add :path, :text, null: false
      add :last_seen_commit, :string, null: false
      add :parsed_at, :utc_datetime, null: false
      add :feature_name, :string, null: false
      add :feature_description, :text
      add :raw_content, :text
      add :feature_version, :string
      add :feature_product, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:specs, [:team_id, :repo_uri, :branch_name, :path])
    create constraint(:specs, :feature_name_url_safe, check: "feature_name ~ '^[a-zA-Z0-9_-]+$'")

    create constraint(:specs, :feature_product_url_safe,
             check: "feature_product ~ '^[a-zA-Z0-9_-]+$'"
           )

    execute """
    CREATE UNIQUE INDEX specs_team_feature_version_unique_idx
    ON specs (team_id, feature_name, COALESCE(feature_version, ''))
    """

    create index(:specs, [:team_id, :feature_name])

    create table(:implementations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :spec_id, references(:specs, type: :uuid, on_delete: :delete_all), null: false
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      add :name, :string, null: false
      add :description, :text
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    create unique_index(:implementations, [:spec_id, :name])

    create table(:tracked_branches, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :implementation_id, references(:implementations, type: :uuid, on_delete: :delete_all),
        null: false

      add :repo_uri, :text, null: false
      add :branch_name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:tracked_branches, [:implementation_id, :repo_uri])

    execute(
      "CREATE TYPE requirement_group_type AS ENUM ('COMPONENT', 'CONSTRAINT')",
      "DROP TYPE requirement_group_type"
    )

    create table(:requirements, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :spec_id, references(:specs, type: :uuid, on_delete: :delete_all), null: false
      add :group_key, :string, null: false
      add :group_type, :requirement_group_type, null: false
      add :local_id, :string, null: false
      add :parent_local_id, :string
      add :definition, :text, null: false
      add :note, :text
      add :is_deprecated, :boolean, null: false, default: false
      add :replaced_by, :jsonb, null: false, default: "[]"
      add :feature_name, :string, null: false

      timestamps(type: :utc_datetime)
    end

    execute(
      """
      ALTER TABLE requirements
      ADD COLUMN acid text GENERATED ALWAYS AS (feature_name || '.' || group_key || '.' || local_id) STORED
      """,
      "ALTER TABLE requirements DROP COLUMN acid"
    )

    create index(:requirements, [:acid])
    create unique_index(:requirements, [:spec_id, :group_key, :local_id])

    create table(:requirement_statuses, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :requirement_id, references(:requirements, type: :uuid, on_delete: :delete_all),
        null: false

      add :implementation_id, references(:implementations, type: :uuid, on_delete: :delete_all),
        null: false

      add :status, :string
      add :is_active, :boolean, null: false, default: true
      add :last_seen_commit, :string, null: false
      add :note, :string

      timestamps(type: :utc_datetime)
    end

    create unique_index(:requirement_statuses, [:implementation_id, :requirement_id])

    create table(:code_references, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      add :requirement_id, references(:requirements, type: :uuid, on_delete: :nothing),
        null: false

      add :branch_id, references(:tracked_branches, type: :uuid, on_delete: :delete_all),
        null: false

      add :repo_uri, :text, null: false
      add :last_seen_commit, :text, null: false
      add :acid_string, :text, null: false
      add :last_seen_at, :utc_datetime
      add :path, :text, null: false
      add :is_test, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end

    create unique_index(:code_references, [:requirement_id, :branch_id, :path])

    create table(:activity_events, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      add :actor_token_id, references(:access_tokens, type: :uuid, on_delete: :nilify_all)
      add :event_type, :string, null: false
      add :subject_type, :string, null: false
      add :subject_id, :uuid, null: false
      add :batch_id, :uuid
      add :payload, :jsonb, null: false, default: "{}"

      timestamps(type: :utc_datetime, inserted_at: :created_at, updated_at: false)
    end

    create index(:activity_events, ["team_id", "created_at DESC"],
             name: :activity_events_team_id_created_at_desc_index
           )

    create index(:activity_events, ["subject_type", "subject_id", "created_at DESC"],
             name: :activity_events_subject_type_subject_id_created_at_desc_index
           )

    create index(:activity_events, [:batch_id])
  end
end
