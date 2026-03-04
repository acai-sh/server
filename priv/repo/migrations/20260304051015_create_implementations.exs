defmodule Acai.Repo.Migrations.CreateImplementations do
  use Ecto.Migration

  def change do
    # data-model.IMPLS.1
    create table(:implementations, primary_key: false) do
      add :id, :uuid, primary_key: true, null: false

      # data-model.IMPLS.2
      add :spec_id, references(:specs, type: :uuid, on_delete: :delete_all), null: false
      # data-model.IMPLS.6
      add :team_id, references(:teams, type: :uuid, on_delete: :delete_all), null: false

      # data-model.IMPLS.3
      add :name, :string, null: false
      # data-model.IMPLS.4
      add :description, :text
      # data-model.IMPLS.5
      add :is_active, :boolean, null: false, default: true

      # data-model.FIELDS.1
      timestamps(type: :utc_datetime)
    end

    # data-model.IMPLS.7
    create unique_index(:implementations, [:spec_id, :name])
  end
end
