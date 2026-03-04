defmodule Acai.Repo.Migrations.CreateCodeReferences do
  use Ecto.Migration

  def change do
    # DATA.REFS.1
    create table(:code_references, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # DATA.REFS.2
      add :requirement_id,
          references(:requirements, type: :uuid, on_delete: :nothing),
          null: false

      # DATA.REFS.3
      add :repo_uri, :text, null: false
      # DATA.REFS.4
      add :branch_name, :text, null: false
      # DATA.REFS.5
      add :last_seen_commit, :text, null: false
      # DATA.REFS.6
      add :acid_string, :text, null: false
      # DATA.REFS.7
      add :last_seen_at, :utc_datetime

      # DATA.FIELDS.1
      timestamps(type: :utc_datetime)
    end
  end
end
