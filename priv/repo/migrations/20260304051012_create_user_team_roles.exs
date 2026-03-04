defmodule Acai.Repo.Migrations.CreateUserTeamRoles do
  use Ecto.Migration

  def change do
    # data-model.ROLES
    create table(:user_team_roles, primary_key: false) do
      # data-model.ROLES.1
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      # data-model.ROLES.2
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # data-model.ROLES.3
      add :title, :string, null: false

      # data-model.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # data-model.ROLES
    create unique_index(:user_team_roles, [:team_id, :user_id])
  end
end
