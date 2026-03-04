defmodule Acai.Repo.Migrations.RemoveFeatureKey do
  use Ecto.Migration

  def up do
    # Remove feature_key from specs
    alter table(:specs) do
      remove :feature_key
    end

    # Remove acid generated column before modifying its dependencies
    execute "ALTER TABLE requirements DROP COLUMN acid"

    # Rename feature_key to feature_name in requirements
    # and update its check constraint
    rename table(:requirements), :feature_key, to: :feature_name

    # Re-create acid generated column using feature_name
    execute """
    ALTER TABLE requirements
    ADD COLUMN acid text GENERATED ALWAYS AS (feature_name || '.' || group_key || '.' || local_id) STORED
    """

    # Re-create index on acid
    create index(:requirements, [:acid])
  end

  def down do
    # Revert requirements.acid
    execute "ALTER TABLE requirements DROP COLUMN acid"

    # Rename feature_name back to feature_key
    rename table(:requirements), :feature_name, to: :feature_key

    # Re-create acid using feature_key
    execute """
    ALTER TABLE requirements
    ADD COLUMN acid text GENERATED ALWAYS AS (feature_key || '.' || group_key || '.' || local_id) STORED
    """

    # Re-create index on acid
    create index(:requirements, [:acid])

    # Add feature_key back to specs
    alter table(:specs) do
      add :feature_key, :string
    end
  end
end
