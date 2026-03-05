defmodule Acai.Repo.Migrations.UpdateCodeReferencesSchema do
  use Ecto.Migration

  def change do
    # Drop the old unique index that included deprecated branch_name (data-model.REFS.4)
    drop_if_exists unique_index(:code_references, [:requirement_id, :repo_uri, :branch_name])

    alter table(:code_references) do
      # data-model.REFS.4 - remove deprecated branch_name field
      remove :branch_name, :text

      # data-model.REFS.8 - file path from repo root including line number
      add :path, :text, null: false

      # data-model.REFS.9 - flag distinguishing test references from production references
      add :is_test, :boolean, default: false, null: false

      # data-model.REFS.10 - foreign key to tracked_branches (replaces branch_name)
      add :branch_id,
          references(:tracked_branches, type: :uuid, on_delete: :delete_all),
          null: false
    end

    # New unique constraint: one ref per requirement per exact file location per branch
    create unique_index(:code_references, [:requirement_id, :branch_id, :path])
  end
end
