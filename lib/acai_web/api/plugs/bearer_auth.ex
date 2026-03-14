defmodule AcaiWeb.Api.Plugs.BearerAuth do
  @moduledoc """
  Plug for bearer token authentication on API routes.

  This plug reads the Authorization header, validates the Bearer token,
  and assigns the authenticated token and team to the connection.

  See push.AUTH.1, core.ENG.8
  """

  import Plug.Conn
  alias Acai.Teams

  @doc """
  Initializes the plug with options.
  """
  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @doc """
  Performs the authentication check.

  Expects an Authorization header in the format: "Bearer <token>"
  Returns 401 if the token is missing, malformed, unknown, revoked, or expired.
  """
  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] ->
        authenticate_token(conn, token)

      [auth_header] ->
        if String.starts_with?(auth_header, "Bearer ") do
          # Empty token after "Bearer "
          unauthorized(conn, "Invalid or missing bearer token")
        else
          unauthorized(conn, "Authorization header must use Bearer scheme")
        end

      [] ->
        unauthorized(conn, "Authorization header required")

      _ ->
        unauthorized(conn, "Invalid Authorization header format")
    end
  end

  defp authenticate_token(conn, raw_token) do
    case Teams.authenticate_api_token(raw_token) do
      {:ok, %{token: token, team: team}} ->
        conn
        |> assign(:current_token, token)
        |> assign(:current_team, team)
        |> assign(:current_team_id, team.id)

      {:error, reason} ->
        unauthorized(conn, reason)
    end
  end

  defp unauthorized(conn, detail) do
    conn
    |> put_status(:unauthorized)
    |> put_resp_content_type("application/json")
    |> Phoenix.Controller.json(%{errors: %{detail: detail}})
    |> halt()
  end
end
