defmodule Acai.Teams.Team do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # data-model.TEAMS.1
  # data-model.FIELDS.2
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "teams" do
    # data-model.TEAMS.2
    # data-model.TEAMS.2-1
    field :name, :string

    # team-list.ENG.1
    has_many :user_team_roles, Acai.Teams.UserTeamRole

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name])
    |> validate_required([:name])
    # data-model.TEAMS.2
    |> update_change(:name, &String.downcase/1)
    # data-model.TEAMS.2-1
    |> validate_url_safe(:name)
    |> unique_constraint(:name)
    |> check_constraint(:name, name: :name_url_safe)
  end
end
