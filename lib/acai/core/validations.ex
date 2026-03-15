defmodule Acai.Core.Validations do
  @moduledoc """
  Shared changeset validation helpers.
  """

  import Ecto.Changeset

  # data-model.TEAMS.2-1
  # data-model.SPECS.7-1
  # data-model.SPECS.9-1
  @url_safe_pattern ~r/^[a-zA-Z0-9_-]+$/

  @doc """
  Validates that a field only contains URL-safe characters (alphanumeric, hyphens, underscores).
  """
  # data-model.TEAMS.2-1
  # data-model.SPECS.7-1
  # data-model.SPECS.9-1
  def validate_url_safe(changeset, field) do
    validate_format(changeset, field, @url_safe_pattern)
  end
end
