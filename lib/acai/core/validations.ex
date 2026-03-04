defmodule Acai.Core.Validations do
  @moduledoc """
  Shared changeset validation helpers.
  """

  import Ecto.Changeset

  # data-model.TEAMS.2-1
  # data-model.SPECS.8-1
  # data-model.SPECS.12-1
  @url_safe_pattern ~r/^[a-zA-Z0-9_-]+$/

  # data-model.FIELDS.2
  @uppercase_key_pattern ~r/^[A-Z0-9_]+$/

  @doc """
  Validates that a field only contains URL-safe characters (alphanumeric, hyphens, underscores).
  """
  # data-model.TEAMS.2-1
  # data-model.SPECS.8-1
  # data-model.SPECS.12-1
  # data-model.FIELDS.2
  def validate_url_safe(changeset, field) do
    validate_format(changeset, field, @url_safe_pattern)
  end

  @doc """
  Validates that a field only contains uppercase alphanumeric characters and underscores.
  Used for `group_key` fields to ensure reliable greppability in code.
  """
  # data-model.FIELDS.2
  def validate_uppercase_key(changeset, field) do
    validate_format(changeset, field, @uppercase_key_pattern)
  end
end
