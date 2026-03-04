defmodule Acai.Repo.Migrations.CreateCodeReferences do
  use Ecto.Migration

  def change do
    # data-model.REFS.1
    create table(:code_references, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # data-model.REFS.2
      add :requirement_id,
          references(:requirements, type: :uuid, on_delete: :nothing),
          null: false

      # data-model.REFS.3
      add :repo_uri, :text, null: false
      # data-model.REFS.4
      add :branch_name, :text, null: false
      # data-model.REFS.5
      add :last_seen_commit, :text, null: false
      # data-model.REFS.6
      add :acid_string, :text, null: false
      # data-model.REFS.7
      add :last_seen_at, :utc_datetime

      # data-model.FIELDS.1
      timestamps(type: :utc_datetime)
    end
  end
end
