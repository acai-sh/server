defmodule Acai.Repo.Migrations.FixDataSchemaIssues do
  use Ecto.Migration

  def change do
    # data-model.TOKENS.6-1 — default scopes for new tokens
    alter table(:access_tokens) do
      modify :scopes, :jsonb,
        null: false,
        default:
          fragment(
            "'[\"specs:read\",\"specs:write\",\"refs:read\",\"refs:write\",\"impls:read\",\"impls:write\",\"team:read\"]'::jsonb"
          )
    end

    # data-model.EVENTS.3 — actor_token_id must nilify on token delete, not cascade
    drop constraint(:activity_events, "activity_events_actor_token_id_fkey")

    alter table(:activity_events) do
      modify :actor_token_id,
             references(:access_tokens, type: :uuid, on_delete: :nilify_all),
             null: true
    end

    # data-model.EVENTS_IDX.1 — drop plain index, replace with DESC on created_at
    drop index(:activity_events, [:team_id, :created_at])

    create index(:activity_events, ["team_id", "created_at DESC"],
             name: :activity_events_team_id_created_at_desc_index
           )

    # data-model.EVENTS_IDX.2 — drop plain index, replace with DESC on created_at
    drop index(:activity_events, [:subject_type, :subject_id, :created_at])

    create index(:activity_events, ["subject_type", "subject_id", "created_at DESC"],
             name: :activity_events_subject_type_subject_id_created_at_desc_index
           )

    # REFS — unique constraint on (requirement_id, repo_uri, branch_name)
    create unique_index(:code_references, [:requirement_id, :repo_uri, :branch_name])

    # data-model.SPECS.8-1 / data-model.SPECS.12-1 / data-model.FIELDS.2 — DB-level check constraints
    create constraint(:specs, :feature_name_url_safe, check: "feature_name ~ '^[a-zA-Z0-9_-]+$'")

    create constraint(:specs, :feature_product_url_safe,
             check: "feature_product ~ '^[a-zA-Z0-9_-]+$'"
           )

    create constraint(:specs, :feature_key_url_safe, check: "feature_key ~ '^[a-zA-Z0-9_-]+$'")
  end
end
