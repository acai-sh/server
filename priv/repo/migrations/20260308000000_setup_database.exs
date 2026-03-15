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
    # data-model.FIELDS.2
    create table(:teams, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.TEAMS.2
      add :name, :citext, null: false

      timestamps(type: :utc_datetime)
    end

    # data-model.TEAMS.2
    create unique_index(:teams, [:name])
    # data-model.TEAMS.2-1
    execute "ALTER TABLE teams ADD CONSTRAINT name_url_safe CHECK (name ~ '^[a-zA-Z0-9_-]+$')"

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
    # data-model.FIELDS.2
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
    execute "ALTER TABLE products ADD CONSTRAINT products_name_url_safe CHECK (name ~ '^[a-zA-Z0-9_-]+$')"

    # ============================================================================
    # ACCESS TOKENS TABLE
    # ============================================================================

    # data-model.TOKENS.1
    # data-model.FIELDS.2
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
    # data-model.FIELDS.2
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
    # BRANCHES TABLE (NEW - stable branch identity)
    # ============================================================================

    # data-model.BRANCHES.1
    # data-model.FIELDS.2
    create table(:branches, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.BRANCHES.6: team_id is a Foreign Key to teams table, non-nullable
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      # data-model.BRANCHES.2
      add :repo_uri, :text, null: false
      # data-model.BRANCHES.3
      add :branch_name, :string, null: false
      # data-model.BRANCHES.4
      add :last_seen_commit, :string, null: false

      timestamps(type: :utc_datetime)
    end

    # data-model.BRANCHES.5: Index on (repo_uri) for listing branches by repository
    create index(:branches, [:repo_uri])

    # data-model.BRANCHES.6-1: Composite Unique Constraint enforces (team_id, repo_uri, branch_name)
    create unique_index(:branches, [:team_id, :repo_uri, :branch_name])

    # ============================================================================
    # TRACKED BRANCHES TABLE (junction table: implementations <-> branches)
    # ============================================================================

    # data-model.TRACKED_BRANCHES.1
    # data-model.TRACKED_BRANCHES.2
    # data-model.TRACKED_BRANCHES.3
    create table(:tracked_branches, primary_key: false) do
      # data-model.TRACKED_BRANCHES.1
      add :implementation_id,
          references(:implementations, type: :uuid, on_delete: :delete_all),
          primary_key: true,
          null: false

      # data-model.TRACKED_BRANCHES.2
      add :branch_id,
          references(:branches, type: :uuid, on_delete: :delete_all),
          primary_key: true,
          null: false

      # data-model.TRACKED_BRANCHES.5
      add :repo_uri, :text, null: false

      timestamps(type: :utc_datetime)
    end

    # data-model.TRACKED_BRANCHES.4
    create unique_index(:tracked_branches, [:implementation_id, :repo_uri])

    # ============================================================================
    # SPECS TABLE
    # ============================================================================

    # data-model.SPECS.1
    # data-model.FIELDS.2
    create table(:specs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.SPECS.2
      add :product_id, references(:products, type: :uuid, on_delete: :delete_all), null: false
      # data-model.SPECS.3
      add :branch_id, references(:branches, type: :uuid, on_delete: :delete_all), null: false
      # data-model.SPECS.4
      add :path, :text
      # data-model.SPECS.5
      add :last_seen_commit, :string, null: false
      # data-model.SPECS.6
      add :parsed_at, :utc_datetime, null: false
      # data-model.SPECS.7
      add :feature_name, :string, null: false
      # data-model.SPECS.8
      add :feature_description, :text
      # data-model.SPECS.9
      add :feature_version, :string, null: false, default: "1.0.0"
      # data-model.SPECS.10
      add :raw_content, :text
      # data-model.SPECS.11
      add :requirements, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    # data-model.SPECS.7-1
    execute "ALTER TABLE specs ADD CONSTRAINT feature_name_url_safe CHECK (feature_name ~ '^[a-zA-Z0-9_-]+$')"

    # data-model.SPECS.12: Composite Unique Constraint enforces (branch_id, feature_name)
    create unique_index(:specs, [:branch_id, :feature_name])
    # data-model.SPECS.14: Index on (branch_id) for joining specs to branches
    create index(:specs, [:branch_id])
    # data-model.SPECS.13
    create index(:specs, [:product_id])

    # ============================================================================
    # FEATURE IMPL STATES TABLE (NEW - replaces requirement_statuses)
    # ============================================================================

    # data-model.FEATURE_IMPL_STATES.1
    # data-model.FIELDS.2
    create table(:feature_impl_states, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.FEATURE_IMPL_STATES.2
      add :implementation_id, references(:implementations, type: :uuid, on_delete: :delete_all),
        null: false

      # data-model.FEATURE_IMPL_STATES.3
      add :feature_name, :string, null: false
      # data-model.FEATURE_IMPL_STATES.4
      add :states, :map, null: false, default: %{}

      timestamps(type: :utc_datetime)
    end

    # data-model.FEATURE_IMPL_STATES.3-1
    execute "ALTER TABLE feature_impl_states ADD CONSTRAINT feature_name_url_safe CHECK (feature_name ~ '^[a-zA-Z0-9_-]+$')"

    # data-model.FEATURE_IMPL_STATES.5
    create unique_index(:feature_impl_states, [:implementation_id, :feature_name])
    # data-model.FEATURE_IMPL_STATES.6
    create index(:feature_impl_states, [:states], using: "gin")
    # data-model.FEATURE_IMPL_STATES.7
    create index(:feature_impl_states, [:implementation_id])

    # ============================================================================
    # FEATURE BRANCH REFS TABLE (NEW - branch-scoped refs)
    # ============================================================================

    # data-model.FEATURE_BRANCH_REFS.1: id field is a UUIDv7 Primary Key
    # data-model.FIELDS.2
    create table(:feature_branch_refs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false
      # data-model.FEATURE_BRANCH_REFS.2: branch_id is a Foreign Key to branches table
      add :branch_id, references(:branches, type: :uuid, on_delete: :delete_all), null: false

      # data-model.FEATURE_BRANCH_REFS.3: feature_name matches the feature.name from spec file
      add :feature_name, :string, null: false
      # data-model.FEATURE_BRANCH_REFS.4: refs is a JSONB column storing ACID references
      # data-model.FEATURE_BRANCH_REFS.4-1: refs format is an object keyed by full ACID string
      # data-model.FEATURE_BRANCH_REFS.4-2: Each ACID entry contains an array of reference objects
      # data-model.FEATURE_BRANCH_REFS.4-3: Each reference object contains path (string), is_test (boolean)
      add :refs, :map, null: false, default: %{}

      # data-model.FEATURE_BRANCH_REFS.5: commit is a string storing the commit hash when refs were pushed
      add :commit, :string, null: false
      # data-model.FEATURE_BRANCH_REFS.6: pushed_at is a timestamp of when the refs were pushed
      add :pushed_at, :utc_datetime, null: false

      timestamps(type: :utc_datetime)
    end

    # data-model.FEATURE_BRANCH_REFS.3-1: feature_name field only supports alphanumeric chars, hyphens, and underscores
    execute "ALTER TABLE feature_branch_refs ADD CONSTRAINT feature_name_url_safe CHECK (feature_name ~ '^[a-zA-Z0-9_-]+$')"

    # data-model.FEATURE_BRANCH_REFS.7: Composite Unique Constraint enforces (branch_id, feature_name)
    create unique_index(:feature_branch_refs, [:branch_id, :feature_name])

    # data-model.FEATURE_BRANCH_REFS.8: GIN Index on (refs) for querying by ACID key within the JSONB
    create index(:feature_branch_refs, [:refs], using: "gin")

    # data-model.FEATURE_BRANCH_REFS.9: Index on (branch_id) for listing all features for a branch
    create index(:feature_branch_refs, [:branch_id])
  end
end
