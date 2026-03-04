defmodule Acai.Teams.UserTeamRole do
  use Ecto.Schema
  import Ecto.Changeset

  alias Acai.Teams.Permissions

  # DATA.ROLES
  @primary_key false
  @foreign_key_type Acai.UUIDv7

  schema "user_team_roles" do
    # DATA.ROLES.1
    belongs_to :team, Acai.Teams.Team
    # DATA.ROLES.2
    belongs_to :user, Acai.Accounts.User, type: :id

    # DATA.ROLES.3
    field :title, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(role, attrs) do
    role
    |> cast(attrs, [:title])
    |> validate_required([:title])
    # ROLES.SCOPES.1
    # ROLES.SCOPES.2
    |> validate_inclusion(:title, Permissions.valid_roles(),
      message: "must be one of: #{Enum.join(Permissions.valid_roles(), ", ")}"
    )
    |> unique_constraint([:team_id, :user_id])
  end
end
