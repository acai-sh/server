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
    render_error(conn, :not_found, "Resource not found")
  end

  def call(conn, {:error, :payload_too_large}) do
    render_error(conn, 413, "Request body too large")
  end

  def call(conn, {:error, :rate_limited}) do
    render_error(conn, 429, "Rate limit exceeded")
  end

  def call(conn, {:error, {:payload_too_large, reason}}) when is_binary(reason) do
    render_error(conn, 413, reason)
  end

  def call(conn, {:error, {:rate_limited, reason}}) when is_binary(reason) do
    render_error(conn, 429, reason)
  end

  # Handle forbidden errors (missing scope/permission).
  # push.RESPONSE.7 - On scope/permission error, returns HTTP 403
  def call(conn, {:error, :forbidden}) do
    render_error(conn, :forbidden, "Access denied")
  end

  def call(conn, {:error, {:forbidden, reason}}) when is_binary(reason) do
    render_error(conn, :forbidden, reason)
  end

  # Handle changeset validation errors.
  def call(conn, {:error, %Changeset{} = changeset}) do
    errors = Changeset.traverse_errors(changeset, &format_error/1)

    render_error(conn, :unprocessable_entity, format_changeset_errors(errors))
  end

  # Handle generic error tuples with a reason string.
  def call(conn, {:error, reason}) when is_binary(reason) do
    render_error(conn, :unprocessable_entity, reason)
  end

  # Handle atom-based error reasons.
  def call(conn, {:error, reason}) when is_atom(reason) do
    render_error(conn, :unprocessable_entity, format_atom_error(reason))
  end

  defp render_error(conn, status, detail) do
    conn = ensure_json_format(conn)

    conn
    |> put_status(status)
    |> put_view(json: AcaiWeb.Api.ErrorJSON)
    |> render(:error, status: status, detail: detail)
  end

  defp ensure_json_format(%{params: %{"_format" => _}} = conn), do: conn

  defp ensure_json_format(conn) do
    conn = Plug.Conn.fetch_query_params(conn)

    %{conn | params: Map.put(conn.params, "_format", "json")}
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
