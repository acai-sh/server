defmodule Acai.Teams do
  @moduledoc """
  Context for teams, user roles, and access tokens.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Teams.{Team, UserTeamRole, AccessToken}

  # --- Teams ---

  def list_teams(current_scope) do
    Repo.all(from t in Team, where: t.id in subquery(team_ids_for_user(current_scope.user.id)))
  end

  def get_team!(id), do: Repo.get!(Team, id)

  def create_team(current_scope, attrs) do
    %Team{}
    |> Team.changeset(attrs)
    |> Ecto.Changeset.put_assoc(:user_team_roles, [
      %UserTeamRole{user_id: current_scope.user.id, title: "owner"}
    ])
    |> Repo.insert()
  end

  def update_team(%Team{} = team, attrs) do
    team
    |> Team.changeset(attrs)
    |> Repo.update()
  end

  def change_team(%Team{} = team, attrs \\ %{}) do
    Team.changeset(team, attrs)
  end

  # --- Roles ---

  def list_user_team_roles(current_scope, %Team{} = team) do
    Repo.all(
      from r in UserTeamRole,
        where: r.team_id == ^team.id and r.user_id == ^current_scope.user.id
    )
  end

  def create_user_team_role(current_scope, %Team{} = team, attrs) do
    %UserTeamRole{}
    |> UserTeamRole.changeset(attrs)
    |> Ecto.Changeset.put_change(:team_id, team.id)
    |> Ecto.Changeset.put_change(:user_id, current_scope.user.id)
    |> Repo.insert()
  end

  @doc """
  Updates the role title for a team member.

  Guards:
  - An owner may not demote themselves.
  - The last owner on a team may not be demoted.
  """
  def update_member_role(current_scope, %UserTeamRole{} = role, new_title) do
    acting_user_id = current_scope.user.id

    # ROLES.SCOPES.7
    if role.title == "owner" && role.user_id == acting_user_id do
      {:error, :self_demotion}
    else
      # ROLES.MODULE.3
      if role.title == "owner" && owner_count(role.team_id) <= 1 do
        {:error, :last_owner}
      else
        changeset = UserTeamRole.changeset(role, %{title: new_title})

        if changeset.valid? do
          {1, _} =
            Repo.update_all(
              from(r in UserTeamRole,
                where: r.team_id == ^role.team_id and r.user_id == ^role.user_id
              ),
              set: [title: new_title]
            )

          {:ok, %{role | title: new_title}}
        else
          {:error, changeset}
        end
      end
    end
  end

  # --- Access Tokens ---

  def list_access_tokens(current_scope, %Team{} = team) do
    Repo.all(
      from t in AccessToken,
        where: t.team_id == ^team.id and t.user_id == ^current_scope.user.id
    )
  end

  def get_access_token!(id), do: Repo.get!(AccessToken, id)

  def create_access_token(current_scope, %Team{} = team, attrs) do
    %AccessToken{}
    |> AccessToken.changeset(attrs)
    |> Ecto.Changeset.put_change(:team_id, team.id)
    |> Ecto.Changeset.put_change(:user_id, current_scope.user.id)
    |> Repo.insert()
  end

  def change_access_token(%AccessToken{} = token, attrs \\ %{}) do
    AccessToken.changeset(token, attrs)
  end

  # --- Private helpers ---

  defp team_ids_for_user(user_id) do
    from r in UserTeamRole, where: r.user_id == ^user_id, select: r.team_id
  end

  # ROLES.MODULE.3
  defp owner_count(team_id) do
    Repo.one(
      from r in UserTeamRole,
        where: r.team_id == ^team_id and r.title == "owner",
        select: count(r.user_id)
    )
  end
end
