defmodule Acai.Repo.Migrations.CreateSpecs do
  use Ecto.Migration

  def change do
    # data-model.SPECS.1
    create table(:specs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # data-model.SPECS.7
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false

      # data-model.SPECS.2
      add :repo_uri, :text, null: false
      # data-model.SPECS.3
      add :branch_name, :string, null: false
      # data-model.SPECS.4
      add :path, :text, null: false
      # data-model.SPECS.5
      add :last_seen_commit, :string, null: false
      # data-model.SPECS.6
      add :parsed_at, :utc_datetime, null: false

      # data-model.SPECS.8
      # data-model.SPECS.8-1
      add :feature_name, :string, null: false
      # data-model.SPECS.9
      # data-model.FIELDS.2
      add :feature_key, :string, null: false
      # data-model.SPECS.10
      add :feature_description, :text
      # data-model.SPECS.11
      add :feature_version, :string
      # data-model.SPECS.12
      # data-model.SPECS.12-1
      add :feature_product, :string, null: false

      # data-model.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # data-model.SPECS.13
    create unique_index(:specs, [:team_id, :repo_uri, :branch_name, :path])
  end
end
