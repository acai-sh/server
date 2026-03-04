defmodule Acai.Repo.Migrations.CreateUserTeamRoles do
  use Ecto.Migration

  def change do
    # DATA.ROLES
    create table(:user_team_roles, primary_key: false) do
      # DATA.ROLES.1
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false
      # DATA.ROLES.2
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # DATA.ROLES.3
      add :title, :string, null: false

      # DATA.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # DATA.ROLES
    create unique_index(:user_team_roles, [:team_id, :user_id])
  end
end
