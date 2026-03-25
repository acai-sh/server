defmodule AcaiWeb.Api.OpenApiControllerTest do
  @moduledoc """
  Tests for the OpenApiController.

  ACIDs:
  - core.API.1 - Exposes public /api/v1/openapi.json route
  - core.API.1-1 - Renders compliant OpenAPI JSON spec
  - core.ENG.3 - Route documentation is defined inline in controllers
  """

  use AcaiWeb.ConnCase, async: true

  describe "GET /api/v1/openapi.json" do
    test "returns valid OpenAPI JSON without authentication", %{conn: conn} do
      conn = get(conn, "/api/v1/openapi.json")

      assert conn.status == 200
      assert get_resp_header(conn, "content-type") == ["application/json; charset=utf-8"]

      {:ok, spec} = Jason.decode(conn.resp_body)

      # Verify it's a valid OpenAPI spec
      assert spec["openapi"] == "3.0.0"
      assert spec["info"]["title"] == "Acai API"
      assert spec["info"]["version"] == "1.0.0"

      # Check for security schemes
      assert spec["components"]["securitySchemes"]["bearerAuth"]["type"] == "http"
      assert spec["components"]["securitySchemes"]["bearerAuth"]["scheme"] == "bearer"

      assert spec["paths"]["/push"]["post"]["operationId"] ==
               "AcaiWeb.Api.PushController.create"
    end

    test "openapi.json route is accessible without Authorization header", %{conn: conn} do
      # Ensure no Authorization header is set
      conn = delete_req_header(conn, "authorization")
      conn = get(conn, "/api/v1/openapi.json")

      assert conn.status == 200
    end
  end
end
