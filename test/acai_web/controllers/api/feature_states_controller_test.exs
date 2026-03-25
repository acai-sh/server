defmodule AcaiWeb.Api.FeatureStatesControllerTest do
  @moduledoc false

  use AcaiWeb.ConnCase, async: false

  import Acai.DataModelFixtures
  import ExUnit.CaptureLog

  alias Acai.AccountsFixtures
  alias Acai.Specs
  alias Acai.Teams

  defp feature_setup(team, opts \\ []) do
    feature_name = Keyword.get(opts, :feature_name, "feature-states-api")
    product = product_fixture(team, %{name: "feature-states-api-product"})

    branch =
      branch_fixture(team, %{repo_uri: "github.com/acai/feature-states", branch_name: "main"})

    parent_impl = implementation_fixture(product, %{name: "Parent"})

    child_impl =
      implementation_fixture(product, %{name: "Child", parent_implementation_id: parent_impl.id})

    tracked_branch_fixture(parent_impl, %{branch: branch})

    spec =
      spec_fixture(product, %{
        feature_name: feature_name,
        branch: branch,
        requirements: %{
          "#{feature_name}.REQ.1" => %{requirement: "One"},
          "#{feature_name}.REQ.2" => %{requirement: "Two"}
        }
      })

    %{
      team: team,
      product: product,
      branch: branch,
      parent_impl: parent_impl,
      child_impl: child_impl,
      spec: spec,
      feature_name: feature_name
    }
  end

  describe "PATCH /api/v1/feature-states" do
    setup do
      original = Application.get_env(:acai, :api_operations)

      on_exit(fn ->
        if is_nil(original) do
          Application.delete_env(:acai, :api_operations)
        else
          Application.put_env(:acai, :api_operations, original)
        end
      end)

      user = AccountsFixtures.user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, token} = Teams.generate_token(%{user: user}, team, %{name: "State Token"})

      %{team: team, user: user, token: token}
    end

    # feature-states.ENDPOINT.1, feature-states.ENDPOINT.2, feature-states.ENDPOINT.3
    # feature-states.REQUEST.1-6, feature-states.RESPONSE.1-4
    test "returns 200 and writes a merged state payload", %{conn: conn, token: token, team: team} do
      ctx = feature_setup(team)

      {:ok, _} =
        Specs.create_feature_impl_state(ctx.feature_name, ctx.parent_impl, %{
          states: %{
            "#{ctx.feature_name}.REQ.1" => %{"status" => "assigned"},
            "#{ctx.feature_name}.REQ.2" => %{"status" => "completed"}
          }
        })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> patch("/api/v1/feature-states", %{
          "product_name" => ctx.product.name,
          "feature_name" => ctx.feature_name,
          "implementation_name" => ctx.child_impl.name,
          "states" => %{
            "#{ctx.feature_name}.REQ.2" => %{"status" => "blocked"}
          }
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["product_name"] == ctx.product.name
      assert data["feature_name"] == ctx.feature_name
      assert data["implementation_name"] == ctx.child_impl.name
      assert data["implementation_id"] == to_string(ctx.child_impl.id)
      assert data["states_written"] == 1
      assert data["warnings"] == []
    end

    # feature-states.RESPONSE.5
    test "returns 404 when the feature cannot be resolved", %{
      conn: conn,
      token: token,
      team: team
    } do
      ctx = feature_setup(team)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> patch("/api/v1/feature-states", %{
          "product_name" => ctx.product.name,
          "feature_name" => "missing-feature",
          "implementation_name" => ctx.child_impl.name,
          "states" => %{"missing-feature.REQ.1" => %{"status" => "completed"}}
        })

      assert json_response(conn, 404)
      assert conn.resp_body =~ "Resource not found"
    end

    # feature-states.RESPONSE.5
    test "returns 404 when the product cannot be resolved", %{
      conn: conn,
      token: token,
      team: team
    } do
      ctx = feature_setup(team)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> patch("/api/v1/feature-states", %{
          "product_name" => "missing-product",
          "feature_name" => ctx.feature_name,
          "implementation_name" => ctx.child_impl.name,
          "states" => %{"#{ctx.feature_name}.REQ.1" => %{"status" => "completed"}}
        })

      assert json_response(conn, 404)
      assert conn.resp_body =~ "Resource not found"
    end

    # feature-states.RESPONSE.5
    test "returns 404 when the implementation cannot be resolved", %{
      conn: conn,
      token: token,
      team: team
    } do
      ctx = feature_setup(team)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> patch("/api/v1/feature-states", %{
          "product_name" => ctx.product.name,
          "feature_name" => ctx.feature_name,
          "implementation_name" => "missing-implementation",
          "states" => %{"#{ctx.feature_name}.REQ.1" => %{"status" => "completed"}}
        })

      assert json_response(conn, 404)
      assert conn.resp_body =~ "Resource not found"
    end

    # feature-states.RESPONSE.6, feature-states.RESPONSE.6-1
    test "returns 422 and logs a safe summary for validation errors", %{
      conn: conn,
      token: token,
      team: team
    } do
      ctx = feature_setup(team)

      log =
        capture_log(fn ->
          conn =
            conn
            |> put_req_header("authorization", "Bearer #{token.raw_token}")
            |> put_req_header("content-type", "application/json")
            |> put_req_header("accept", "application/json")
            |> patch("/api/v1/feature-states", %{
              "product_name" => ctx.product.name,
              "feature_name" => ctx.feature_name,
              "implementation_name" => ctx.child_impl.name,
              "states" => %{"other-feature.REQ.1" => %{"status" => "completed"}}
            })

          assert json_response(conn, 422)
        end)

      assert log =~ "api_rejection"
      assert log =~ "feature-states-api-product"
      refute log =~ token.raw_token
    end

    # feature-states.RESPONSE.7, feature-states.RESPONSE.8
    test "returns 401 without auth and 403 when a required scope is missing", %{
      conn: conn,
      team: team,
      user: user
    } do
      ctx = feature_setup(team)

      unauthenticated_conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> patch("/api/v1/feature-states", %{
          "product_name" => ctx.product.name,
          "feature_name" => ctx.feature_name,
          "implementation_name" => ctx.child_impl.name,
          "states" => %{"#{ctx.feature_name}.REQ.1" => %{"status" => "completed"}}
        })

      assert json_response(unauthenticated_conn, 401)

      {:ok, limited_token} =
        Teams.generate_token(%{user: user}, team, %{
          name: "Limited",
          scopes: ["impls:read", "specs:read"]
        })

      forbidden_conn =
        conn
        |> put_req_header("authorization", "Bearer #{limited_token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> patch("/api/v1/feature-states", %{
          "product_name" => ctx.product.name,
          "feature_name" => ctx.feature_name,
          "implementation_name" => ctx.child_impl.name,
          "states" => %{"#{ctx.feature_name}.REQ.1" => %{"status" => "completed"}}
        })

      assert json_response(forbidden_conn, 403)
      assert forbidden_conn.resp_body =~ "states:write"
    end

    # feature-states.RESPONSE.9, feature-states.ABUSE.1, feature-states.ABUSE.1-1
    test "returns 413 when the request body exceeds the configured size cap", %{
      conn: conn,
      token: token,
      team: team
    } do
      Application.put_env(:acai, :api_operations, %{
        default: %{
          request_size_cap: 1,
          semantic_caps: %{},
          rate_limit: %{requests: 60, window_seconds: 60}
        },
        feature_states: %{}
      })

      ctx = feature_setup(team)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> put_req_header("content-length", "10")
        |> patch("/api/v1/feature-states", %{
          "product_name" => ctx.product.name,
          "feature_name" => ctx.feature_name,
          "implementation_name" => ctx.child_impl.name,
          "states" => %{"#{ctx.feature_name}.REQ.1" => %{"status" => "completed"}}
        })

      assert json_response(conn, 413)
      assert conn.resp_body =~ "Request body too large"
    end

    # feature-states.RESPONSE.10, feature-states.ABUSE.4-1
    test "returns 429 when the rate limit is exceeded", %{conn: conn, token: token, team: team} do
      Application.put_env(:acai, :api_operations, %{
        default: %{
          request_size_cap: 2_000_000,
          semantic_caps: %{},
          rate_limit: %{requests: 1, window_seconds: 60}
        },
        feature_states: %{}
      })

      ctx = feature_setup(team)

      first_conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> patch("/api/v1/feature-states", %{
          "product_name" => ctx.product.name,
          "feature_name" => ctx.feature_name,
          "implementation_name" => ctx.child_impl.name,
          "states" => %{"#{ctx.feature_name}.REQ.1" => %{"status" => "completed"}}
        })

      assert json_response(first_conn, 200)

      second_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> patch("/api/v1/feature-states", %{
          "product_name" => ctx.product.name,
          "feature_name" => ctx.feature_name,
          "implementation_name" => ctx.child_impl.name,
          "states" => %{"#{ctx.feature_name}.REQ.1" => %{"status" => "completed"}}
        })

      assert json_response(second_conn, 429)
      assert second_conn.resp_body =~ "Rate limit exceeded"
    end
  end
end
