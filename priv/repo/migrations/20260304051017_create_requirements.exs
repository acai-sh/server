defmodule Acai.Repo.Migrations.CreateRequirements do
  use Ecto.Migration

  def change do
    # DATA.REQS.4
    execute(
      "CREATE TYPE requirement_group_type AS ENUM ('COMPONENT', 'CONSTRAINT')",
      "DROP TYPE requirement_group_type"
    )

    # DATA.REQS.1
    create table(:requirements, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # DATA.REQS.2
      add :spec_id, references(:specs, type: :uuid, on_delete: :delete_all), null: false

      # DATA.REQS.3
      # DATA.FIELDS.2
      add :group_key, :string, null: false
      # DATA.REQS.4
      add :group_type, :requirement_group_type, null: false
      # DATA.REQS.5
      add :local_id, :string, null: false
      # DATA.REQS.6
      add :parent_local_id, :string
      # DATA.REQS.7
      add :definition, :text, null: false
      # DATA.REQS.8
      add :note, :text
      # DATA.REQS.9
      add :is_deprecated, :boolean, null: false, default: false
      # DATA.REQS.10
      add :replaced_by, :jsonb, null: false, default: "[]"
      # DATA.REQS.11
      # DATA.FIELDS.2
      add :feature_key, :string, null: false

      # DATA.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # DATA.REQS.12
    execute(
      """
      ALTER TABLE requirements
      ADD COLUMN acid text GENERATED ALWAYS AS (feature_key || '.' || group_key || '.' || local_id) STORED
      """,
      "ALTER TABLE requirements DROP COLUMN acid"
    )

    # DATA.REQS.12
    create index(:requirements, [:acid])

    # DATA.REQS.13
    create unique_index(:requirements, [:spec_id, :group_key, :local_id])
  end
end
