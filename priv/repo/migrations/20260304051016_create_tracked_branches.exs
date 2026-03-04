defmodule Acai.Repo.Migrations.CreateTrackedBranches do
  use Ecto.Migration

  def change do
    # data-model.BRANCHES.1
    create table(:tracked_branches, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # data-model.BRANCHES.2
      add :implementation_id,
          references(:implementations, type: :uuid, on_delete: :delete_all),
          null: false

      # data-model.BRANCHES.3
      add :repo_uri, :text, null: false
      # data-model.BRANCHES.4
      add :branch_name, :string, null: false

      # data-model.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # data-model.BRANCHES.5
    create unique_index(:tracked_branches, [:implementation_id, :repo_uri])
  end
end
