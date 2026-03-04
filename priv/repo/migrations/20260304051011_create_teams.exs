defmodule Acai.Repo.Migrations.CreateTeams do
  use Ecto.Migration

  def change do
    # data-model.TEAMS.1
    create table(:teams, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # data-model.TEAMS.2
      # data-model.TEAMS.2-1
      add :name, :citext, null: false

      # data-model.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    create unique_index(:teams, [:name])

    # data-model.TEAMS.2-1
    create constraint(:teams, :name_url_safe, check: "name ~ '^[a-zA-Z0-9_-]+$'")
  end
end
