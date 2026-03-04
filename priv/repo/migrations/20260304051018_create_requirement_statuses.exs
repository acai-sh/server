defmodule Acai.Repo.Migrations.CreateRequirementStatuses do
  use Ecto.Migration

  def change do
    # data-model.REQ_STATUSES.1
    create table(:requirement_statuses, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # data-model.REQ_STATUSES.2
      add :requirement_id,
          references(:requirements, type: :uuid, on_delete: :delete_all),
          null: false

      # data-model.REQ_STATUSES.3
      add :implementation_id,
          references(:implementations, type: :uuid, on_delete: :delete_all),
          null: false

      # data-model.REQ_STATUSES.4
      add :status, :string
      # data-model.REQ_STATUSES.5
      add :is_active, :boolean, null: false, default: true
      # data-model.REQ_STATUSES.6
      add :last_seen_commit, :string, null: false

      # data-model.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # data-model.REQ_STATUSES.7
    create unique_index(:requirement_statuses, [:implementation_id, :requirement_id])
  end
end
