defmodule AcaiWeb.Api.FallbackControllerTest do
  @moduledoc """
  Tests for the API FallbackController.

  ACIDs:
  - core.ENG.4 - All HTTP 2xx JSON responses wrap their payload in a root `data` key
  - core.ENG.5 - Controllers use action_fallback for unified error handling
  - core.OPERATIONS.2 - Rejections are logged through the application logger
  """

  use AcaiWeb.ConnCase, async: true

  alias AcaiWeb.Api.FallbackController
  alias Ecto.Changeset

  describe "fallback error handling" do
    test "renders 404 for :not_found errors", %{conn: conn} do
      conn = fetch_query_params(conn)

      conn =
        conn
        |> put_private(:phoenix_action, :test)
        |> put_private(:phoenix_format, "json")
        |> FallbackController.call({:error, :not_found})

      assert conn.status == 404

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Resource not found"
    end

    test "renders 413 for payload too large errors", %{conn: conn} do
      conn = fetch_query_params(conn)

      conn =
        conn
        |> put_private(:phoenix_action, :test)
        |> put_private(:phoenix_format, "json")
        |> FallbackController.call({:error, :payload_too_large})

      assert conn.status == 413

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Request body too large"
    end

    test "renders 429 for rate limited errors", %{conn: conn} do
      conn = fetch_query_params(conn)

      conn =
        conn
        |> put_private(:phoenix_action, :test)
        |> put_private(:phoenix_format, "json")
        |> FallbackController.call({:error, :rate_limited})

      assert conn.status == 429

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Rate limit exceeded"
    end

    test "renders 422 for changeset errors", %{conn: conn} do
      conn = fetch_query_params(conn)

      changeset =
        %Acai.Teams.Team{}
        |> Changeset.change()
        |> Changeset.add_error(:name, "can't be blank")

      conn =
        conn
        |> put_private(:phoenix_action, :test)
        |> put_private(:phoenix_format, "json")
        |> FallbackController.call({:error, changeset})

      assert conn.status == 422

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] =~ "name: can't be blank"
    end

    test "renders 422 for string error messages", %{conn: conn} do
      conn = fetch_query_params(conn)

      conn =
        conn
        |> put_private(:phoenix_action, :test)
        |> put_private(:phoenix_format, "json")
        |> FallbackController.call({:error, "Custom error message"})

      assert conn.status == 422

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Custom error message"
    end

    test "renders 422 for known atom error reasons", %{conn: conn} do
      conn = fetch_query_params(conn)

      conn =
        conn
        |> put_private(:phoenix_action, :test)
        |> put_private(:phoenix_format, "json")
        |> FallbackController.call({:error, :already_member})

      assert conn.status == 422

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "User is already a member of this team"
    end

    test "renders 422 for last_owner atom error", %{conn: conn} do
      conn = fetch_query_params(conn)

      conn =
        conn
        |> put_private(:phoenix_action, :test)
        |> put_private(:phoenix_format, "json")
        |> FallbackController.call({:error, :last_owner})

      assert conn.status == 422

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Cannot remove the last owner of a team"
    end

    test "renders 422 for self_demotion atom error", %{conn: conn} do
      conn = fetch_query_params(conn)

      conn =
        conn
        |> put_private(:phoenix_action, :test)
        |> put_private(:phoenix_format, "json")
        |> FallbackController.call({:error, :self_demotion})

      assert conn.status == 422

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "You cannot demote yourself"
    end

    test "renders 422 for unknown atom errors", %{conn: conn} do
      conn = fetch_query_params(conn)

      conn =
        conn
        |> put_private(:phoenix_action, :test)
        |> put_private(:phoenix_format, "json")
        |> FallbackController.call({:error, :unknown_error})

      assert conn.status == 422

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "unknown_error"
    end
  end

  describe "error response format" do
    test "error response includes detail and status", %{conn: conn} do
      conn = fetch_query_params(conn)

      conn =
        conn
        |> put_private(:phoenix_action, :test)
        |> put_private(:phoenix_format, "json")
        |> FallbackController.call({:error, :not_found})

      {:ok, body} = Jason.decode(conn.resp_body)
      assert body["errors"]["detail"] == "Resource not found"
      assert body["errors"]["status"] == "NOT_FOUND"
    end
  end
end
