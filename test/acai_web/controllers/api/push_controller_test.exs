defmodule AcaiWeb.Api.PushControllerTest do
  @moduledoc """
  Tests for the PushController.

  ACIDs:
  - push.ENDPOINT.1 - POST /api/v1/push
  - push.ENDPOINT.2 - Content-Type application/json
  - push.ENDPOINT.3 - Requires Authorization Bearer token header
  - push.REQUEST.9 - Accepts optional `product_name` string
  - push.AUTH.4 - Refs-only implementation scope enforcement
  - push.LINK_IMPLS.5 - Rejects incomplete refs-only link requests
  - core.ENG.1 - API router pipeline includes OpenApiSpex.Plug.CastAndValidate
  - core.ENG.3 - OpenApi route documentation is defined inline in controllers
  - core.ENG.5 - Controllers use action_fallback for unified error handling
  - core.OPERATIONS.1 - API abuse protections and limits are enforced at runtime
  - push.RESPONSE.1 - On success, returns HTTP 200 with a JSON body containing a `data` object
  - push.RESPONSE.5 - On validation error, returns HTTP 422
  - push.RESPONSE.6 - On auth error, returns HTTP 401
  - push.RESPONSE.7 - On scope/permission error, returns HTTP 403
  - push.RESPONSE.8 - On oversized request body, returns HTTP 413
  - push.RESPONSE.9 - On rate limit exceeded, returns HTTP 429
  """

  use AcaiWeb.ConnCase, async: false

  import Acai.DataModelFixtures
  alias Acai.AccountsFixtures
  alias Acai.Teams

  @valid_push_params %{
    repo_uri: "github.com/test-org/test-repo",
    branch_name: "main",
    commit_hash: "abc123def456",
    specs: [
      %{
        feature: %{
          name: "test-feature",
          product: "test-product",
          description: "A test feature",
          version: "1.0.0"
        },
        requirements: %{
          "test-feature.REQ.1" => %{
            requirement: "Must do something"
          }
        },
        meta: %{
          path: "features/test.feature.yaml",
          last_seen_commit: "abc123def456"
        }
      }
    ]
  }

  describe "POST /api/v1/push" do
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

      # Generate a token with all required scopes
      {:ok, token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Test Token"}
        )

      %{team: team, user: user, token: token}
    end

    test "returns 401 when Authorization header is missing", %{conn: conn} do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", @valid_push_params)

      assert json_response(conn, 401)
      assert conn.resp_body =~ "Authorization header required"
    end

    test "returns 401 when token is invalid", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer invalid_token")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", @valid_push_params)

      assert json_response(conn, 401)
      assert conn.resp_body =~ "Invalid token"
    end

    test "returns 401 when Authorization header is malformed", %{conn: conn} do
      conn =
        conn
        |> put_req_header("authorization", "Basic sometoken")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", @valid_push_params)

      assert json_response(conn, 401)
      assert conn.resp_body =~ "Authorization header must use Bearer scheme"
    end

    test "returns 403 when token is missing required scopes", %{
      conn: conn,
      team: team,
      user: user
    } do
      # Create a token with limited scopes
      {:ok, limited_token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Limited Token", scopes: ["specs:read"]}
        )

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{limited_token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", @valid_push_params)

      assert json_response(conn, 403)
      assert conn.resp_body =~ "specs:write"
    end

    # push.AUTH.4
    test "returns 403 when refs-only request would create an implementation without impls:write",
         %{
           conn: conn,
           team: team,
           user: user
         } do
      product = product_fixture(team, %{name: "child-product"})
      _parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      {:ok, limited_token} =
        Teams.generate_token(
          %{user: user},
          team,
          %{name: "Refs Only", scopes: ["refs:write"]}
        )

      refs_only_child_params = %{
        repo_uri: "github.com/test-org/child-repo",
        branch_name: "child-branch",
        commit_hash: "def789ghi012",
        product_name: "child-product",
        target_impl_name: "child-impl",
        parent_impl_name: "parent-impl",
        references: %{
          data: %{
            "child-feature.REQ.1" => [
              %{path: "lib/child.ex:10", is_test: false}
            ]
          }
        }
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{limited_token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", refs_only_child_params)

      assert json_response(conn, 403)
      assert conn.resp_body =~ "impls:write"
    end

    test "returns 429 when the shared rate limit is exceeded", %{conn: conn, token: token} do
      Application.put_env(:acai, :api_operations, %{
        default: %{
          request_size_cap: 2_000_000,
          semantic_caps: %{},
          rate_limit: %{requests: 1, window_seconds: 60}
        },
        push: %{
          rate_limit: %{requests: 1, window_seconds: 60}
        }
      })

      first_conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", @valid_push_params)

      assert json_response(first_conn, 200)

      second_conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", @valid_push_params)

      assert json_response(second_conn, 429)
      assert second_conn.resp_body =~ "Rate limit exceeded"
    end

    # push.RESPONSE.8
    test "returns 413 when the request body exceeds the configured size cap", %{
      conn: conn,
      token: token
    } do
      Application.put_env(:acai, :api_operations, %{
        default: %{
          request_size_cap: 1,
          semantic_caps: %{},
          rate_limit: %{requests: 1, window_seconds: 60}
        },
        push: %{
          request_size_cap: 1,
          semantic_caps: %{},
          rate_limit: %{requests: 1, window_seconds: 60}
        }
      })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", Jason.encode!(@valid_push_params))

      assert json_response(conn, 413)
      assert conn.resp_body =~ "Request body too large"
    end

    test "successfully pushes specs and creates implementation", %{
      conn: conn,
      token: token,
      team: _team
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", @valid_push_params)

      response = json_response(conn, 200)

      # push.RESPONSE.1 - Response has data object
      assert response["data"]

      # push.RESPONSE.2 - Check response fields
      assert response["data"]["branch_id"]
      assert response["data"]["implementation_name"] == "main"
      assert response["data"]["product_name"] == "test-product"
      assert response["data"]["implementation_id"]

      # push.RESPONSE.3 - Specs counts
      assert response["data"]["specs_created"] == 1
      assert response["data"]["specs_updated"] == 0

      # push.RESPONSE.4 - Warnings array
      assert is_list(response["data"]["warnings"])
    end

    test "successfully pushes refs only (no specs)", %{conn: conn, token: token} do
      # First push specs to create implementation
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", @valid_push_params)

      assert json_response(conn, 200)

      # Now push only refs
      refs_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "def789ghi012",
        references: %{
          data: %{
            "test-feature.REQ.1" => [
              %{path: "lib/test.ex:42", is_test: false}
            ]
          }
        }
      }

      conn =
        build_conn()
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", refs_params)

      response = json_response(conn, 200)
      assert response["data"]["specs_created"] == 0
      assert response["data"]["specs_updated"] == 0
    end

    # push.NEW_IMPLS.6, push.NEW_IMPLS.6-1, push.NEW_IMPLS.6-2, push.RESPONSE.1, push.RESPONSE.2
    test "creates a child implementation from refs-only inputs", %{
      conn: conn,
      token: token,
      team: team
    } do
      product = product_fixture(team, %{name: "child-product"})
      _parent_impl = implementation_fixture(product, %{name: "parent-impl"})

      refs_only_child_params = %{
        repo_uri: "github.com/test-org/child-repo",
        branch_name: "child-branch",
        commit_hash: "def789ghi012",
        product_name: "child-product",
        target_impl_name: "child-impl",
        parent_impl_name: "parent-impl",
        references: %{
          data: %{
            "child-feature.REQ.1" => [
              %{path: "lib/child.ex:10", is_test: false}
            ]
          }
        }
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", refs_only_child_params)

      response = json_response(conn, 200)

      assert response["data"]["implementation_name"] == "child-impl"
      assert response["data"]["product_name"] == "child-product"
      assert response["data"]["implementation_id"]
      assert response["data"]["branch_id"]
    end

    test "returns 422 when required fields are missing", %{conn: conn, token: token} do
      invalid_params = %{
        # Missing repo_uri, branch_name, commit_hash
        specs: []
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", invalid_params)

      assert json_response(conn, 422)
    end

    # push.VALIDATION.7, push.VALIDATION.8, push.VALIDATION.9
    test "returns 422 when refs-only implementation inputs are incomplete", %{
      conn: conn,
      token: token
    } do
      invalid_params = %{
        repo_uri: "github.com/test-org/new-repo",
        branch_name: "feature-branch",
        commit_hash: "abc123def456",
        references: %{
          data: %{
            "some-feature.REQ.1" => [
              %{path: "lib/test.ex:42", is_test: false}
            ]
          }
        },
        product_name: "test-product"
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", invalid_params)

      assert json_response(conn, 422)
      assert conn.resp_body =~ "rule set"
    end

    # push.LINK_IMPLS.5, push.VALIDATION.9
    test "returns 422 when refs-only product_name and target_impl_name do not resolve to an existing implementation",
         %{conn: conn, token: token} do
      invalid_params = %{
        repo_uri: "github.com/test-org/new-repo",
        branch_name: "feature-branch",
        commit_hash: "abc123def456",
        references: %{
          data: %{
            "some-feature.REQ.1" => [
              %{path: "lib/test.ex:42", is_test: false}
            ]
          }
        },
        product_name: "test-product",
        target_impl_name: "missing-impl"
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", invalid_params)

      assert json_response(conn, 422)
      assert conn.resp_body =~ "existing implementation"
    end

    test "returns 422 when request body fails OpenAPI validation", %{conn: conn, token: token} do
      invalid_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "abc123def456",
        specs: %{}
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", invalid_params)

      assert json_response(conn, 422)
    end

    test "returns 422 when states are pushed to untracked branch", %{
      conn: conn,
      token: token
    } do
      # Try to push states without first pushing specs
      states_params = %{
        repo_uri: "github.com/test-org/new-repo",
        branch_name: "feature-branch",
        commit_hash: "abc123def456",
        states: %{
          data: %{
            "some-feature.REQ.1" => %{
              status: "completed"
            }
          }
        }
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", states_params)

      assert json_response(conn, 422)
      assert conn.resp_body =~ "Cannot push states"
    end

    test "returns 422 and flattens changeset errors when spec validation fails", %{
      conn: conn,
      token: token
    } do
      invalid_spec_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "abc123def456",
        specs: [
          %{
            feature: %{
              name: "invalid feature name",
              product: "test-product",
              description: "A test feature",
              version: "1.0.0"
            },
            requirements: %{
              "test-feature.REQ.1" => %{
                requirement: "Must do something"
              }
            },
            meta: %{
              path: "features/test.feature.yaml",
              last_seen_commit: "abc123def456"
            }
          }
        ]
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", invalid_spec_params)

      assert json_response(conn, 422)
      assert conn.resp_body =~ "feature_name"
    end

    test "rejects multi-product push", %{conn: conn, token: token} do
      multi_product_params = %{
        repo_uri: "github.com/test-org/test-repo",
        branch_name: "main",
        commit_hash: "abc123def456",
        specs: [
          %{
            feature: %{
              name: "feature-1",
              product: "product-a"
            },
            requirements: %{"feature-1.REQ.1" => %{requirement: "Do something"}},
            meta: %{path: "f1.yaml", last_seen_commit: "abc"}
          },
          %{
            feature: %{
              name: "feature-2",
              product: "product-b"
            },
            requirements: %{"feature-2.REQ.1" => %{requirement: "Do something else"}},
            meta: %{path: "f2.yaml", last_seen_commit: "abc"}
          }
        ]
      }

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> put_req_header("content-type", "application/json")
        |> put_req_header("accept", "application/json")
        |> post(~p"/api/v1/push", multi_product_params)

      assert json_response(conn, 422)
      assert conn.resp_body =~ "multiple products"
    end
  end
end
