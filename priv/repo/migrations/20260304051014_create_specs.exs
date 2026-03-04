defmodule Acai.Repo.Migrations.CreateSpecs do
  use Ecto.Migration

  def change do
    # DATA.SPECS.1
    create table(:specs, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # DATA.SPECS.7
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false

      # DATA.SPECS.2
      add :repo_uri, :text, null: false
      # DATA.SPECS.3
      add :branch_name, :string, null: false
      # DATA.SPECS.4
      add :path, :text, null: false
      # DATA.SPECS.5
      add :last_seen_commit, :string, null: false
      # DATA.SPECS.6
      add :parsed_at, :utc_datetime, null: false

      # DATA.SPECS.8
      # DATA.SPECS.8-1
      add :feature_name, :string, null: false
      # DATA.SPECS.9
      # DATA.FIELDS.2
      add :feature_key, :string, null: false
      # DATA.SPECS.10
      add :feature_description, :text
      # DATA.SPECS.11
      add :feature_version, :string
      # DATA.SPECS.12
      # DATA.SPECS.12-1
      add :feature_product, :string, null: false

      # DATA.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # DATA.SPECS.13
    create unique_index(:specs, [:team_id, :repo_uri, :branch_name, :path])
  end
end
