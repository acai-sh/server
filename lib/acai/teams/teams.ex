defmodule Acai.Teams do
  @moduledoc """
  Context for teams, user roles, and access tokens.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Teams.{Team, UserTeamRole, AccessToken}
  alias Acai.Accounts
  alias Acai.Accounts.{User, UserNotifier}

  # --- Teams ---

  def list_teams(current_scope) do
    Repo.all(from t in Team, where: t.id in subquery(team_ids_for_user(current_scope.user.id)))
  end

  def get_team!(id), do: Repo.get!(Team, id)
  def get_team_by_name!(name), do: Repo.get_by!(Team, name: name)

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

  # team-settings.DELETE.5
  def delete_team(%Team{} = team) do
    Repo.delete(team)
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

  # team-view.MEMBERS.1
  def list_team_members(%Team{} = team) do
    Repo.all(
      from r in UserTeamRole,
        where: r.team_id == ^team.id,
        preload: [:user]
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
  Invites a user to the team by email.

  Finds or creates the user, adds them with the given role, and sends
  an appropriate email. Returns an error if they are already a member.
  """
  # team-view.INVITE.3-1
  # team-view.INVITE.3-2
  # team-view.INVITE.3-3
  # team-view.INVITE.3-4
  def invite_member(%Team{} = team, email, role, login_url_fn) do
    Repo.transact(fn ->
      already_member? =
        Repo.exists?(
          from r in UserTeamRole,
            where: r.team_id == ^team.id,
            join: u in User,
            on: u.id == r.user_id,
            where: u.email == ^email
        )

      if already_member? do
        # team-view.INVITE.3-1
        {:error, :already_member}
      else
        # team-view.INVITE.3-2
        user =
          case Accounts.get_user_by_email(email) do
            nil ->
              {:ok, new_user} = Accounts.register_user(%{email: email})
              new_user

            existing ->
              existing
          end

        result =
          %UserTeamRole{}
          |> UserTeamRole.changeset(%{title: role})
          |> Ecto.Changeset.put_change(:team_id, team.id)
          |> Ecto.Changeset.put_change(:user_id, user.id)
          |> Repo.insert()

        case result do
          {:ok, role} ->
            # team-view.INVITE.3-3
            if is_nil(user.confirmed_at) do
              Accounts.deliver_login_instructions(user, login_url_fn)
            else
              UserNotifier.deliver_team_added_notification(user, team.name)
            end

            {:ok, %{role | user: user}}

          {:error, changeset} ->
            {:error, changeset}
        end
      end
    end)
  end

  @doc """
  Removes a member from the team and revokes all their access tokens for that team.

  Guards against removing the last owner.
  """
  # team-view.DELETE_ROLE.3
  # team-view.DELETE_ROLE.4
  def remove_member(%Team{} = team, user_id) do
    role =
      Repo.one(
        from r in UserTeamRole,
          where: r.team_id == ^team.id and r.user_id == ^user_id
      )

    cond do
      is_nil(role) ->
        {:error, :not_found}

      # team-view.DELETE_ROLE.4
      role.title == "owner" && owner_count(team.id) <= 1 ->
        {:error, :last_owner}

      true ->
        Repo.transact(fn ->
          now = DateTime.utc_now(:second)

          # team-view.DELETE_ROLE.3
          Repo.update_all(
            from(t in AccessToken,
              where: t.team_id == ^team.id and t.user_id == ^user_id and is_nil(t.revoked_at)
            ),
            set: [revoked_at: now]
          )

          Repo.delete_all(
            from r in UserTeamRole,
              where: r.team_id == ^team.id and r.user_id == ^user_id
          )

          {:ok, :removed}
        end)
    end
  end

  @doc """
  Updates the role title for a team member.

  Guards:
  - An owner may not demote themselves.
  - The last owner on a team may not be demoted.
  """
  def update_member_role(current_scope, %UserTeamRole{} = role, new_title) do
    acting_user_id = current_scope.user.id

    # team-roles.SCOPES.7
    if role.title == "owner" && role.user_id == acting_user_id do
      {:error, :self_demotion}
    else
      # team-roles.MODULE.3
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

  # team-tokens.MAIN.1
  # team-tokens.TATSEC.5
  def list_team_tokens(%Team{} = team) do
    now = DateTime.utc_now()

    Repo.all(
      from t in AccessToken,
        where:
          t.team_id == ^team.id and is_nil(t.revoked_at) and
            (is_nil(t.expires_at) or t.expires_at > ^now),
        order_by: [desc: t.inserted_at],
        preload: [:user]
    )
  end

  # team-tokens.INACTIVE.1
  def list_inactive_team_tokens(%Team{} = team) do
    now = DateTime.utc_now()

    Repo.all(
      from t in AccessToken,
        where:
          t.team_id == ^team.id and
            (not is_nil(t.revoked_at) or (not is_nil(t.expires_at) and t.expires_at <= ^now)),
        order_by: [desc: coalesce(t.revoked_at, t.expires_at)],
        preload: [:user]
    )
  end

  def get_access_token!(id), do: Repo.get!(AccessToken, id)

  def create_access_token(current_scope, %Team{} = team, attrs, timezone_offset \\ 0) do
    %AccessToken{}
    |> AccessToken.changeset(attrs, timezone_offset)
    |> Ecto.Changeset.put_change(:team_id, team.id)
    |> Ecto.Changeset.put_change(:user_id, current_scope.user.id)
    |> Repo.insert()
  end

  @doc """
  Generates a new cryptographically secure access token, hashes it, and persists
  only the hash and prefix. Returns {:ok, token} with the raw_token virtual field
  populated for one-time display, or {:error, changeset}.
  """
  # team-tokens.MAIN.3
  # team-tokens.TATSEC.1
  # team-tokens.TATSEC.2
  def generate_token(current_scope, %Team{} = team, attrs, timezone_offset \\ 0) do
    raw_bytes = :crypto.strong_rand_bytes(32)
    encoded = Base.url_encode64(raw_bytes, padding: false)
    raw_token = "at_" <> encoded
    # team-tokens.TATSEC.1
    token_prefix = "at_" <> String.slice(encoded, 0, 6)
    token_hash = :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)

    is_string_keys = Enum.any?(attrs, fn {k, _} -> is_binary(k) end)

    token_attrs =
      if is_string_keys do
        attrs
        |> Map.put("token_hash", token_hash)
        |> Map.put("token_prefix", token_prefix)
      else
        attrs
        |> Map.put(:token_hash, token_hash)
        |> Map.put(:token_prefix, token_prefix)
      end

    case create_access_token(current_scope, team, token_attrs, timezone_offset) do
      {:ok, token} ->
        token_with_user = Repo.preload(token, :user)
        {:ok, %{token_with_user | raw_token: raw_token}}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Revokes a token by setting revoked_at to the current UTC time.
  """
  # team-tokens.MAIN.5
  # team-tokens.TATSEC.4
  def revoke_token(%AccessToken{} = token) do
    now = DateTime.utc_now(:second)

    token
    |> Ecto.Changeset.change(revoked_at: now)
    |> Repo.update()
  end

  @doc """
  Returns true if the token is currently valid (not revoked, not expired).
  """
  # team-tokens.TATSEC.3
  def valid_token?(%AccessToken{} = token) do
    not_revoked = is_nil(token.revoked_at)

    not_expired =
      case token.expires_at do
        nil -> true
        expires_at -> DateTime.compare(DateTime.utc_now(), expires_at) == :lt
      end

    not_revoked and not_expired
  end

  def change_access_token(%AccessToken{} = token, attrs \\ %{}, timezone_offset \\ 0) do
    AccessToken.changeset(token, attrs, timezone_offset)
  end

  @doc """
  Authenticates an API token from its raw string value.

  Hashes the presented token, looks up the record, validates it is not
  revoked or expired, updates last_used_at, and returns the token with
  its associated team.

  Returns {:ok, %{token: token, team: team}} on success,
  or {:error, reason_string} on failure.

  See push.AUTH.1
  """
  def authenticate_api_token(raw_token) do
    token_hash = hash_token(raw_token)

    case Repo.get_by(AccessToken, token_hash: token_hash) do
      nil ->
        {:error, "Invalid token"}

      token ->
        token = Repo.preload(token, :team)

        cond do
          not is_nil(token.revoked_at) ->
            {:error, "Token has been revoked"}

          not is_nil(token.expires_at) and
              DateTime.compare(DateTime.utc_now(), token.expires_at) == :gt ->
            {:error, "Token has expired"}

          true ->
            # Update last_used_at
            now = DateTime.utc_now(:second)

            updated_token =
              token
              |> Ecto.Changeset.change(last_used_at: now)
              |> Repo.update!()

            {:ok, %{token: updated_token, team: token.team}}
        end
    end
  end

  @doc """
  Checks if the given token has the required scope.

  See push.AUTH.2-5
  """
  def token_has_scope?(%AccessToken{} = token, required_scope) do
    required_scope in (token.scopes || [])
  end

  defp hash_token(raw_token) do
    :crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)
  end

  # --- Private helpers ---

  defp team_ids_for_user(user_id) do
    from r in UserTeamRole, where: r.user_id == ^user_id, select: r.team_id
  end

  # team-roles.MODULE.3
  defp owner_count(team_id) do
    Repo.one(
      from r in UserTeamRole,
        where: r.team_id == ^team_id and r.title == "owner",
        select: count(r.user_id)
    )
  end
end
