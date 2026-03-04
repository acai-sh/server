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
end
