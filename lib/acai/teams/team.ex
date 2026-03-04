defmodule Acai.Teams.Team do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # DATA.TEAMS.1
  # DATA.FIELDS.3
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "teams" do
    # DATA.TEAMS.2
    # DATA.TEAMS.2-1
    field :name, :string

    # TEAMS.ENG.1
    has_many :user_team_roles, Acai.Teams.UserTeamRole

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(team, attrs) do
    team
    |> cast(attrs, [:name])
    |> validate_required([:name])
    # DATA.TEAMS.2
    |> update_change(:name, &String.downcase/1)
    # DATA.TEAMS.2-1
    |> validate_url_safe(:name)
    |> unique_constraint(:name)
    |> check_constraint(:name, name: :name_url_safe)
  end
end
