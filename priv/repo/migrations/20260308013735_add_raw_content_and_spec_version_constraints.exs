defmodule Acai.Repo.Migrations.AddRawContentAndSpecVersionConstraints do
  use Ecto.Migration

  def up do
    alter table(:specs) do
      # data-model.SPECS.10
      add :raw_content, :text
    end

    # data-model.SPECS.14
    # Uses COALESCE to treat NULL version as empty string, so:
    # - (team_id=1, feature_name="foo", feature_version=NULL) conflicts with another (team_id=1, feature_name="foo", feature_version=NULL)
    # - This forces users to version their specs when duplicating across branches
    execute """
    CREATE UNIQUE INDEX specs_team_feature_version_unique_idx
    ON specs (team_id, feature_name, COALESCE(feature_version, ''))
    """

    # data-model.SPECS.15
    create index(:specs, [:team_id, :feature_name])
  end

  def down do
    execute "DROP INDEX IF EXISTS specs_team_feature_version_unique_idx"
    drop index(:specs, [:team_id, :feature_name])

    alter table(:specs) do
      remove :raw_content
    end
  end
end
