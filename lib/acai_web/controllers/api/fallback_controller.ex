defmodule AcaiWeb.Api.FallbackController do
  @moduledoc """
  Fallback controller for API controllers.

  Handles errors consistently across all API endpoints, producing
  JSON responses wrapped in the standard error format.

  See core.ENG.4, core.ENG.5
  """

  use AcaiWeb, :controller

  alias Ecto.Changeset

  @doc """
  Handles errors for API responses.
  """

  # Handle not found errors.
  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: AcaiWeb.Api.ErrorJSON)
    |> render(:error, status: :not_found, detail: "Resource not found")
  end

  # Handle forbidden errors (missing scope/permission).
  # push.RESPONSE.7 - On scope/permission error, returns HTTP 403
  def call(conn, {:error, :forbidden}) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: AcaiWeb.Api.ErrorJSON)
    |> render(:error, status: :forbidden, detail: "Access denied")
  end

  def call(conn, {:error, {:forbidden, reason}}) when is_binary(reason) do
    conn
    |> put_status(:forbidden)
    |> put_view(json: AcaiWeb.Api.ErrorJSON)
    |> render(:error, status: :forbidden, detail: reason)
  end

  # Handle changeset validation errors.
  def call(conn, {:error, %Changeset{} = changeset}) do
    errors = Changeset.traverse_errors(changeset, &format_error/1)

    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: AcaiWeb.Api.ErrorJSON)
    |> render(:error, status: :unprocessable_entity, detail: format_changeset_errors(errors))
  end

  # Handle generic error tuples with a reason string.
  def call(conn, {:error, reason}) when is_binary(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: AcaiWeb.Api.ErrorJSON)
    |> render(:error, status: :unprocessable_entity, detail: reason)
  end

  # Handle atom-based error reasons.
  def call(conn, {:error, reason}) when is_atom(reason) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: AcaiWeb.Api.ErrorJSON)
    |> render(:error, status: :unprocessable_entity, detail: format_atom_error(reason))
  end

  defp format_error({msg, opts}) do
    Regex.replace(~r"%\{(\w+)\}", msg, fn _, key ->
      opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
    end)
  end

  defp format_changeset_errors(errors) when is_map(errors) do
    errors
    |> Enum.map(fn {field, messages} ->
      messages = List.wrap(messages)
      "#{field}: #{Enum.join(messages, ", ")}"
    end)
    |> Enum.join("; ")
  end

  defp format_atom_error(:already_member), do: "User is already a member of this team"
  defp format_atom_error(:last_owner), do: "Cannot remove the last owner of a team"
  defp format_atom_error(:self_demotion), do: "You cannot demote yourself"
  defp format_atom_error(reason), do: to_string(reason)
end
