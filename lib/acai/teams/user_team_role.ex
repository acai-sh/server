defmodule Acai.Teams.UserTeamRole do
  use Ecto.Schema
  import Ecto.Changeset

  alias Acai.Teams.Permissions

  # data-model.ROLES
  @primary_key false
  @foreign_key_type Acai.UUIDv7

  schema "user_team_roles" do
    # data-model.ROLES.1
    belongs_to :team, Acai.Teams.Team
    # data-model.ROLES.2
    belongs_to :user, Acai.Accounts.User, type: :id

    # data-model.ROLES.3
    field :title, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:title])
    |> validate_required([:title])
    # team-roles.SCOPES.1
    # team-roles.SCOPES.2
    |> validate_inclusion(:title, Permissions.valid_roles(),
      message: "must be one of: #{Enum.join(Permissions.valid_roles(), ", ")}"
    )
    |> unique_constraint([:team_id, :user_id])
  end
end
