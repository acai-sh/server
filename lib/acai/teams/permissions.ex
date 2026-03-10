defmodule Acai.Teams.Permissions do
  @moduledoc """
  Defines the hardcoded role-to-scope mapping for team members.
  All permissions logic must be accessed through this module.
  """

  # team-roles.SCOPES.1
  @valid_roles ~w(readonly developer owner)

  # team-roles.SCOPES.3
  # data-model.TOKENS.6-1
  @all_scopes ~w(specs:read specs:write states:read states:write refs:read refs:write impls:read impls:write team:read team:admin tats:admin)

  # team-roles.MODULE.2
  @role_scopes %{
    # team-roles.SCOPES.4
    "owner" => @all_scopes,
    # team-roles.SCOPES.5
    "developer" => @all_scopes -- ~w(team:admin tats:admin),
    # team-roles.SCOPES.6
    "readonly" => ~w(specs:read states:read refs:read impls:read team:read)
  }

  @doc """
  Returns the list of supported role strings.
  """
  # team-roles.SCOPES.1
  def valid_roles, do: @valid_roles

  @doc """
  Returns the list of scope strings granted to the given role.
  Returns an empty list for unknown roles.
  """
  # team-roles.MODULE.2
  def scopes_for(role), do: Map.get(@role_scopes, role, [])

  @doc """
  Returns true if the given role has the given scope tag, false otherwise.
  """
  # team-roles.MODULE.1
  def has_permission?(role, scope_tag), do: scope_tag in scopes_for(role)
end
