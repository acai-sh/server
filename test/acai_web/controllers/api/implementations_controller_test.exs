defmodule AcaiWeb.Api.ImplementationsControllerTest do
  @moduledoc false

  use AcaiWeb.ConnCase, async: false

  import Acai.DataModelFixtures

  alias Acai.AccountsFixtures
  alias Acai.Teams

  describe "GET /api/v1/implementations" do
    setup do
      user = AccountsFixtures.user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, token} = Teams.generate_token(%{user: user}, team, %{name: "Read Token"})

      %{team: team, user: user, token: token}
    end

    # implementations.ENDPOINT.2, implementations.RESPONSE.9
    test "returns 401 when authorization is missing", %{conn: conn} do
      conn = get(conn, "/api/v1/implementations", %{"product_name" => "api"})

      assert json_response(conn, 401)
      assert conn.resp_body =~ "Authorization header required"
    end

    # implementations.RESPONSE.8, implementations.FILTERS.3, implementations.FILTERS.4
    test "returns 422 when branch filters are incomplete", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/implementations", %{
          "product_name" => "api",
          "repo_uri" => "github.com/acai/api"
        })

      assert json_response(conn, 422)
      assert conn.resp_body =~ "branch_name is required when repo_uri is provided"
    end

    # implementations.RESPONSE.9, implementations.FILTERS.5, implementations.FILTERS.6
    test "returns 403 when feature filtering is requested without specs scope", %{
      conn: conn,
      team: team,
      user: user
    } do
      {:ok, limited_token} =
        Teams.generate_token(%{user: user}, team, %{
          name: "Impl Read Only",
          scopes: ["impls:read"]
        })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{limited_token.raw_token}")
        |> get("/api/v1/implementations", %{
          "product_name" => "api",
          "feature_name" => "alpha"
        })

      assert json_response(conn, 403)
      assert conn.resp_body =~ "specs:read"
    end

    # implementations.RESPONSE.1, implementations.RESPONSE.2, implementations.RESPONSE.4, implementations.RESPONSE.5, implementations.RESPONSE.6
    test "returns alphabetically sorted implementations for a product", %{
      conn: conn,
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "api"})

      _zulu = implementation_fixture(product, %{name: "Zulu"})
      _alpha = implementation_fixture(product, %{name: "Alpha"})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/implementations", %{"product_name" => "api"})

      assert %{"data" => data} = json_response(conn, 200)
      assert data["product_name"] == "api"
      assert Enum.map(data["implementations"], & &1["implementation_name"]) == ["Alpha", "Zulu"]
    end

    # implementations.FILTERS.1, implementations.FILTERS.2, implementations.FILTERS.5, implementations.RESPONSE.3, implementations.RESPONSE.7
    test "filters by exact branch and feature availability", %{
      conn: conn,
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "api"})

      branch_main = branch_fixture(team, %{repo_uri: "github.com/acai/api", branch_name: "main"})
      branch_dev = branch_fixture(team, %{repo_uri: "github.com/acai/api", branch_name: "dev"})

      impl_main = implementation_fixture(product, %{name: "Main", is_active: true})
      impl_dev = implementation_fixture(product, %{name: "Dev", is_active: true})

      tracked_branch_fixture(impl_main, %{branch: branch_main})
      tracked_branch_fixture(impl_dev, %{branch: branch_dev})

      feature_name = "lookup-feature"
      spec_fixture(product, %{feature_name: feature_name, branch: branch_main})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/implementations", %{
          "product_name" => "api",
          "repo_uri" => "github.com/acai/api",
          "branch_name" => "main",
          "feature_name" => feature_name
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["repo_uri"] == "github.com/acai/api"
      assert data["branch_name"] == "main"
      assert [%{"implementation_name" => "Main"}] = data["implementations"]
    end

    # implementations.FILTERS.5, implementations.FILTERS.6
    test "includes inherited feature matches without local specs", %{
      conn: conn,
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "api"})

      parent = implementation_fixture(product, %{name: "Parent", is_active: true})

      child =
        implementation_fixture(product, %{
          name: "Child",
          is_active: true,
          parent_implementation_id: parent.id
        })

      branch = branch_fixture(team, %{repo_uri: "github.com/acai/api", branch_name: "main"})
      tracked_branch_fixture(parent, %{branch: branch})
      tracked_branch_fixture(child, %{branch: branch})

      feature_name = "inherited-feature"
      spec_fixture(product, %{feature_name: feature_name, branch: branch})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/implementations", %{
          "product_name" => "api",
          "feature_name" => feature_name
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert Enum.map(data["implementations"], & &1["implementation_name"]) == ["Child", "Parent"]
    end

    # implementations.RESPONSE.7
    test "returns an empty list when nothing matches", %{conn: conn, token: token, team: team} do
      _product = product_fixture(team, %{name: "api"})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/implementations", %{
          "product_name" => "api",
          "feature_name" => "missing-feature"
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["implementations"] == []
    end
  end
end
