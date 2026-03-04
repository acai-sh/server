defmodule Acai.Repo.Migrations.AddNoteToRequirementStatuses do
  use Ecto.Migration

  def change do
    alter table(:requirement_statuses) do
      # data-model.REQ_STATUSES.8
      add :note, :string
    end
  end
end
