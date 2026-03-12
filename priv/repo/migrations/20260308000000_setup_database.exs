defmodule Acai.Repo.Migrations.SetupDatabase do
  use Ecto.Migration

  def change do
    execute "CREATE EXTENSION IF NOT EXISTS citext", ""

    # ============================================================================
    # AUTHENTICATION TABLES (from phx.gen.auth - unchanged)
    # ============================================================================

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

    # ============================================================================
    # TEAM & ACCESS CONTROL TABLES
    # ============================================================================

    # data-model.TEAMS.1
    # data-model.FIELDS.3
    create table(:teams, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.TEAMS.2
      add :name, :citext, null: false

      timestamps(type: :utc_datetime)
    end

    # data-model.TEAMS.2
    create unique_index(:teams, [:name])
    # data-model.TEAMS.2-1
    create constraint(:teams, :name_url_safe, check: "name ~ '^[a-zA-Z0-9_-]+$'")

    # data-model.ROLES
    create table(:user_team_roles, primary_key: false) do
      # data-model.ROLES.1
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      # data-model.ROLES.2
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # data-model.ROLES.3
      add :title, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # data-model.ROLES (unique constraint prevents duplicates)
    create unique_index(:user_team_roles, [:team_id, :user_id])

    # ============================================================================
    # PRODUCT TABLE (NEW)
    # ============================================================================

    # data-model.PRODUCTS.1
    # data-model.FIELDS.3
    create table(:products, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.PRODUCTS.2
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      # data-model.PRODUCTS.3
      add :name, :citext, null: false
      # data-model.PRODUCTS.4
      add :description, :text
      # data-model.PRODUCTS.5
      add :is_active, :boolean, null: false, default: true

      timestamps(type: :utc_datetime)
    end

    # data-model.PRODUCTS.6
    create unique_index(:products, [:team_id, :name])
    # data-model.PRODUCTS.3-1
    create constraint(:products, :products_name_url_safe, check: "name ~ '^[a-zA-Z0-9_-]+$'")

    # ============================================================================
    # ACCESS TOKENS TABLE
    # ============================================================================

    # data-model.TOKENS.1
    # data-model.FIELDS.3
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
      # data-model.TOKENS.6-1
      add :scopes, :jsonb, null: false

      # data-model.TOKENS.7
      add :expires_at, :utc_datetime
      # data-model.TOKENS.8
      add :revoked_at, :utc_datetime
      # data-model.TOKENS.9
      add :last_used_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    # data-model.TOKENS.4-1
    create unique_index(:access_tokens, [:token_hash])

    # ============================================================================
    # IMPLEMENTATIONS TABLE
    # ============================================================================

    # data-model.IMPLS.1
    # data-model.FIELDS.3
    create table(:implementations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.IMPLS.2
      add :product_id, references(:products, type: :uuid, on_delete: :delete_all), null: false
      # data-model.IMPLS.3
      add :name, :string, null: false
      # data-model.IMPLS.4
      add :description, :text
      # data-model.IMPLS.5
      add :is_active, :boolean, null: false, default: true
      # data-model.IMPLS.6
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      # data-model.IMPLS.7
      # data-model.IMPLS.7-1
      add :parent_implementation_id,
          references(:implementations, type: :uuid, on_delete: :nilify_all)

      timestamps(type: :utc_datetime)
    end

    # data-model.IMPLS.8
    create unique_index(:implementations, [:product_id, :name])

    # ============================================================================
    # TRACKED BRANCHES TABLE
    # ============================================================================

    # data-model.BRANCHES.1
    # data-model.FIELDS.3
    create table(:tracked_branches, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.BRANCHES.2
      add :implementation_id, references(:implementations, type: :uuid, on_delete: :delete_all),
        null: false

      # data-model.BRANCHES.3
      add :repo_uri, :text, null: false
      # data-model.BRANCHES.4
      add :branch_name, :string, null: false
      # data-model.BRANCHES.5
      add :last_seen_commit, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # data-model.BRANCHES.6
    create unique_index(:tracked_branches, [:implementation_id, :repo_uri])
    # data-model.BRANCHES.7
    create index(:tracked_branches, [:repo_uri, :branch_name])

    # ============================================================================
    # SPECS TABLE
    # ============================================================================

    # data-model.SPECS.1
    # data-model.FIELDS.3
    create table(:specs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.SPECS.2
      add :product_id, references(:products, type: :uuid, on_delete: :delete_all), null: false
      # data-model.SPECS.3
      add :tracked_branch_id, references(:tracked_branches, type: :uuid, on_delete: :nilify_all)
      # data-model.SPECS.4
      add :repo_uri, :text, null: false
      # data-model.SPECS.5
      add :branch_name, :string, null: false
      # data-model.SPECS.6
      add :path, :text
      # data-model.SPECS.7
      add :last_seen_commit, :string, null: false
      # data-model.SPECS.8
      add :parsed_at, :utc_datetime, null: false
      # data-model.SPECS.9
      add :feature_name, :string, null: false
      # data-model.SPECS.10
      add :feature_description, :text
      # data-model.SPECS.11
      add :feature_version, :string, null: false, default: "1.0.0"
      # data-model.SPECS.12
      add :raw_content, :text
      # data-model.SPECS.13
      add :requirements, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    # data-model.SPECS.9-1
    create constraint(:specs, :feature_name_url_safe, check: "feature_name ~ '^[a-zA-Z0-9_-]+$'")

    # data-model.SPECS.14, data-model.SPECS.15
    # If you want to insert a new spec, you have to change either the product, the branch, or the feature name
    create unique_index(:specs, [:product_id, :repo_uri, :branch_name, :feature_name])
    create unique_index(:specs, [:product_id, :feature_name, :feature_version])

    # data-model.SPECS.16
    create index(:specs, [:product_id])
    # data-model.SPECS.17
    create index(:specs, [:repo_uri, :branch_name])

    # ============================================================================
    # SPEC IMPL STATES TABLE (NEW - replaces requirement_statuses)
    # ============================================================================

    # data-model.SPEC_IMPL_STATES.1
    # data-model.FIELDS.3
    create table(:spec_impl_states, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.SPEC_IMPL_STATES.2
      add :implementation_id, references(:implementations, type: :uuid, on_delete: :delete_all),
        null: false

      # data-model.SPEC_IMPL_STATES.3
      add :spec_id, references(:specs, type: :uuid, on_delete: :delete_all), null: false
      # data-model.SPEC_IMPL_STATES.4
      add :states, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    # data-model.SPEC_IMPL_STATES.5
    create unique_index(:spec_impl_states, [:implementation_id, :spec_id])
    # data-model.SPEC_IMPL_STATES.6
    create index(:spec_impl_states, [:states], using: "gin")

    # ============================================================================
    # SPEC IMPL REFS TABLE (NEW - replaces code_references)
    # ============================================================================

    # data-model.SPEC_IMPL_REFS.1
    # data-model.FIELDS.3
    create table(:spec_impl_refs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.SPEC_IMPL_REFS.2
      add :implementation_id, references(:implementations, type: :uuid, on_delete: :delete_all),
        null: false

      # data-model.SPEC_IMPL_REFS.3
      add :spec_id, references(:specs, type: :uuid, on_delete: :delete_all), null: false
      # data-model.SPEC_IMPL_REFS.4
      add :refs, :map, null: false, default: %{}
      # data-model.SPEC_IMPL_REFS.5
      add :agent, :string, null: false
      # data-model.SPEC_IMPL_REFS.6
      add :commit, :string, null: false
      # data-model.SPEC_IMPL_REFS.7
      add :pushed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    # data-model.SPEC_IMPL_REFS.8
    create unique_index(:spec_impl_refs, [:implementation_id, :spec_id])
    # data-model.SPEC_IMPL_REFS.9
    create index(:spec_impl_refs, [:refs], using: "gin")
  end
end
