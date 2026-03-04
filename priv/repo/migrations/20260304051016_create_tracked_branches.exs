defmodule Acai.Repo.Migrations.CreateTrackedBranches do
  use Ecto.Migration

  def change do
    # DATA.BRANCHES.1
    create table(:tracked_branches, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # DATA.BRANCHES.2
      add :implementation_id,
          references(:implementations, type: :uuid, on_delete: :delete_all),
          null: false

      # DATA.BRANCHES.3
      add :repo_uri, :text, null: false
      # DATA.BRANCHES.4
      add :branch_name, :string, null: false

      # DATA.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # DATA.BRANCHES.5
    create unique_index(:tracked_branches, [:implementation_id, :repo_uri])
  end
end
