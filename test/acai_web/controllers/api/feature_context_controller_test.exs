defmodule AcaiWeb.Api.FeatureContextControllerTest do
  @moduledoc false

  use AcaiWeb.ConnCase, async: false

  import Acai.DataModelFixtures

  alias Acai.AccountsFixtures
  alias Acai.Specs
  alias Acai.Teams

  describe "GET /api/v1/feature-context" do
    setup do
      user = AccountsFixtures.user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, token} = Teams.generate_token(%{user: user}, team, %{name: "Read Token"})

      %{team: team, user: user, token: token}
    end

    # feature-context.ENDPOINT.2, feature-context.RESPONSE.15
    test "returns 401 when authorization is missing", %{conn: conn} do
      conn =
        get(conn, "/api/v1/feature-context", %{
          "product_name" => "api",
          "feature_name" => "feature",
          "implementation_name" => "prod"
        })

      assert json_response(conn, 401)
      assert conn.resp_body =~ "Authorization header required"
    end

    # feature-context.RESPONSE.16
    test "returns 403 when a required scope is missing", %{conn: conn, team: team, user: user} do
      {:ok, limited_token} =
        Teams.generate_token(%{user: user}, team, %{
          name: "Limited",
          scopes: ["impls:read", "specs:read", "refs:read"]
        })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{limited_token.raw_token}")
        |> get("/api/v1/feature-context", %{
          "product_name" => "api",
          "feature_name" => "feature",
          "implementation_name" => "prod"
        })

      assert json_response(conn, 403)
      assert conn.resp_body =~ "states:read"
    end

    # feature-context.RESPONSE.14
    test "returns 422 when statuses include an invalid value", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/feature-context", %{
          "product_name" => "api",
          "feature_name" => "feature",
          "implementation_name" => "prod",
          "statuses" => ["bogus"]
        })

      assert json_response(conn, 422)
      assert conn.resp_body =~ "statuses contains an invalid value"
    end

    # feature-context.RESPONSE.13
    test "returns 404 when the feature cannot be resolved", %{
      conn: conn,
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "api"})
      impl = implementation_fixture(product, %{name: "prod"})

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/feature-context", %{
          "product_name" => "api",
          "feature_name" => "missing",
          "implementation_name" => impl.name
        })

      assert json_response(conn, 404)
      assert conn.resp_body =~ "Resource not found"
    end

    # feature-context.RESPONSE.1, feature-context.RESPONSE.2, feature-context.RESPONSE.3, feature-context.RESPONSE.4, feature-context.RESPONSE.5, feature-context.RESPONSE.8, feature-context.RESPONSE.9, feature-context.RESPONSE.10, feature-context.REQUEST.7-1
    test "returns canonical feature context with refs, dangling states, and repeated status filters",
         %{
           conn: conn,
           token: token,
           team: team
         } do
      product = product_fixture(team, %{name: "api"})
      impl = implementation_fixture(product, %{name: "prod"})
      branch = branch_fixture(team, %{repo_uri: "github.com/acai/api", branch_name: "main"})

      tracked_branch_fixture(impl, %{branch: branch})

      feature_name = "context-feature"

      spec =
        spec_fixture(product, %{
          feature_name: feature_name,
          branch: branch,
          requirements: %{
            "#{feature_name}.REQ.1" => %{requirement: "Completed"},
            "#{feature_name}.REQ.2" => %{requirement: "Unset"},
            "#{feature_name}.REQ.3" => %{requirement: "Blocked"}
          }
        })

      {:ok, _} =
        Specs.create_feature_impl_state(feature_name, impl, %{
          states: %{
            "#{feature_name}.REQ.1" => %{"status" => "completed", "comment" => "done"},
            "#{feature_name}.REQ.2" => %{"status" => nil},
            "#{feature_name}.REQ.3" => %{"status" => "blocked"},
            "#{feature_name}.OLD.1" => %{"status" => "accepted"}
          }
        })

      feature_branch_ref_fixture(branch, feature_name, %{
        refs: %{
          "#{feature_name}.REQ.1" => [
            %{"path" => "lib/acai/example.ex:1", "is_test" => false}
          ]
        }
      })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/feature-context", %{
          "product_name" => "api",
          "feature_name" => feature_name,
          "implementation_name" => "prod",
          "include_refs" => true,
          "include_dangling_states" => true,
          "include_deprecated" => true,
          "statuses" => ["null", "completed"]
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["product_name"] == "api"
      assert data["feature_name"] == feature_name
      assert data["implementation_name"] == "prod"
      assert data["spec_source"]["source_type"] == "local"
      assert data["states_source"]["source_type"] == "local"
      assert data["refs_source"]["source_type"] == "local"
      assert data["summary"]["total_acids"] == 2
      assert data["summary"]["status_counts"] == %{"completed" => 1, "null" => 1}
      assert length(data["acids"]) == 2
      assert length(data["dangling_states"]) == 1
      assert length(data["warnings"]) == 1
      assert hd(data["acids"])["refs_count"] == 1
      assert hd(data["acids"])["state"]["status"] in [nil, "completed"]
      assert spec.feature_name == feature_name
    end
  end
end
