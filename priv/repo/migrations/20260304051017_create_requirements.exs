defmodule Acai.Repo.Migrations.CreateRequirements do
  use Ecto.Migration

  def change do
    # data-model.REQS.4
    execute(
      "CREATE TYPE requirement_group_type AS ENUM ('COMPONENT', 'CONSTRAINT')",
      "DROP TYPE requirement_group_type"
    )

    # data-model.REQS.1
    create table(:requirements, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # data-model.REQS.2
      add :spec_id, references(:specs, type: :uuid, on_delete: :delete_all), null: false

      # data-model.REQS.3
      # data-model.FIELDS.2
      add :group_key, :string, null: false
      # data-model.REQS.4
      add :group_type, :requirement_group_type, null: false
      # data-model.REQS.5
      add :local_id, :string, null: false
      # data-model.REQS.6
      add :parent_local_id, :string
      # data-model.REQS.7
      add :definition, :text, null: false
      # data-model.REQS.8
      add :note, :text
      # data-model.REQS.9
      add :is_deprecated, :boolean, null: false, default: false
      # data-model.REQS.10
      add :replaced_by, :jsonb, null: false, default: "[]"
      # data-model.REQS.11
      # data-model.FIELDS.2
      add :feature_key, :string, null: false

      # data-model.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # data-model.REQS.12
    execute(
      """
      ALTER TABLE requirements
      ADD COLUMN acid text GENERATED ALWAYS AS (feature_key || '.' || group_key || '.' || local_id) STORED
      """,
      "ALTER TABLE requirements DROP COLUMN acid"
    )

    # data-model.REQS.12
    create index(:requirements, [:acid])

    # data-model.REQS.13
    create unique_index(:requirements, [:spec_id, :group_key, :local_id])
  end
end
