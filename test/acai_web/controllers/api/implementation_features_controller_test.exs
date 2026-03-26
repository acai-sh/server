defmodule AcaiWeb.Api.ImplementationFeaturesControllerTest do
  @moduledoc false

  use AcaiWeb.ConnCase, async: false

  import Acai.DataModelFixtures

  alias Acai.AccountsFixtures
  alias Acai.Teams

  # implementation-features.DISCOVERY.1, implementation-features.DISCOVERY.2, implementation-features.DISCOVERY.4, implementation-features.DISCOVERY.5, implementation-features.RESPONSE.2, implementation-features.RESPONSE.3, implementation-features.RESPONSE.4, implementation-features.RESPONSE.5, implementation-features.RESPONSE.6, implementation-features.RESPONSE.7
  defp worklist_setup(team) do
    product = product_fixture(team, %{name: "controller-worklist"})

    parent = implementation_fixture(product, %{name: "Parent"})

    child =
      implementation_fixture(product, %{
        name: "Child",
        parent_implementation_id: parent.id
      })

    child_branch =
      branch_fixture(team, %{repo_uri: "github.com/acai/controller", branch_name: "main"})

    parent_branch =
      branch_fixture(team, %{repo_uri: "github.com/acai/controller", branch_name: "parent"})

    tracked_branch_fixture(child, %{branch: child_branch})
    tracked_branch_fixture(parent, %{branch: parent_branch})

    spec_fixture(product, %{
      feature_name: "alpha",
      branch: child_branch,
      repo_uri: child_branch.repo_uri,
      feature_description: "Local alpha",
      requirements: %{
        "alpha.REQ.1" => %{requirement: "Alpha one"}
      }
    })

    spec_fixture(product, %{
      feature_name: "beta",
      branch: parent_branch,
      repo_uri: parent_branch.repo_uri,
      feature_description: "Inherited beta",
      requirements: %{
        "beta.REQ.1" => %{requirement: "Beta one"}
      }
    })

    {:ok, _} =
      Acai.Specs.create_feature_impl_state("alpha", child, %{
        states: %{
          "alpha.REQ.1" => %{"status" => "completed"}
        }
      })

    {:ok, _} =
      Acai.Specs.create_feature_impl_state("beta", parent, %{
        states: %{
          "beta.REQ.1" => %{"status" => "assigned"}
        }
      })

    feature_branch_ref_fixture(child_branch, "alpha", %{
      refs: %{
        "alpha.REQ.1" => [%{"path" => "lib/alpha.ex:1", "is_test" => false}]
      },
      commit: "alpha-ref"
    })

    feature_branch_ref_fixture(parent_branch, "beta", %{
      refs: %{
        "beta.REQ.1" => [%{"path" => "test/beta_test.exs:1", "is_test" => true}]
      },
      commit: "beta-ref"
    })

    %{
      product: product,
      child: child,
      parent: parent,
      child_branch: child_branch,
      parent_branch: parent_branch
    }
  end

  describe "GET /api/v1/implementation-features" do
    setup do
      user = AccountsFixtures.user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, token} = Teams.generate_token(%{user: user}, team, %{name: "Read Token"})

      %{team: team, user: user, token: token}
    end

    # implementation-features.ENDPOINT.2, implementation-features.RESPONSE.10
    test "returns 401 when authorization is missing", %{conn: conn} do
      conn = get(conn, "/api/v1/implementation-features", %{"product_name" => "api"})

      assert json_response(conn, 401)
      assert conn.resp_body =~ "Authorization header required"
    end

    # implementation-features.RESPONSE.11
    test "returns 403 when a required scope is missing", %{conn: conn, team: team, user: user} do
      {:ok, limited_token} =
        Teams.generate_token(%{user: user}, team, %{
          name: "Limited",
          scopes: ["impls:read", "specs:read", "states:read"]
        })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{limited_token.raw_token}")
        |> get("/api/v1/implementation-features", %{
          "product_name" => "api",
          "implementation_name" => "prod"
        })

      assert json_response(conn, 403)
      assert conn.resp_body =~ "refs:read"
    end

    # implementation-features.RESPONSE.8
    test "returns 422 when statuses contain an invalid value", %{conn: conn, token: token} do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/implementation-features", %{
          "product_name" => "api",
          "implementation_name" => "prod",
          "statuses" => ["bogus"]
        })

      assert json_response(conn, 422)
      assert conn.resp_body =~ "statuses contains an invalid value"
    end

    # implementation-features.RESPONSE.9
    test "returns 404 when the product cannot be resolved", %{
      conn: conn,
      token: token,
      team: team
    } do
      _ctx = worklist_setup(team)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/implementation-features", %{
          "product_name" => "missing-product",
          "implementation_name" => "Child"
        })

      assert json_response(conn, 404)
      assert conn.resp_body =~ "Resource not found"
    end

    # implementation-features.RESPONSE.9
    test "returns 404 when the implementation cannot be resolved", %{
      conn: conn,
      token: token,
      team: team
    } do
      ctx = worklist_setup(team)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/implementation-features", %{
          "product_name" => ctx.product.name,
          "implementation_name" => "missing-implementation"
        })

      assert json_response(conn, 404)
      assert conn.resp_body =~ "Resource not found"
    end

    # implementation-features.RESPONSE.1, implementation-features.RESPONSE.2, implementation-features.RESPONSE.3, implementation-features.RESPONSE.4, implementation-features.RESPONSE.5, implementation-features.RESPONSE.6, implementation-features.RESPONSE.7
    test "returns canonical feature summaries for the implementation", %{
      conn: conn,
      token: token,
      team: team
    } do
      ctx = worklist_setup(team)

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/implementation-features", %{
          "product_name" => ctx.product.name,
          "implementation_name" => ctx.child.name
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert data["product_name"] == ctx.product.name
      assert data["implementation_name"] == ctx.child.name
      assert data["implementation_id"] == to_string(ctx.child.id)
      assert Enum.map(data["features"], & &1["feature_name"]) == ["alpha", "beta"]

      alpha = Enum.find(data["features"], &(&1["feature_name"] == "alpha"))
      beta = Enum.find(data["features"], &(&1["feature_name"] == "beta"))

      assert alpha["description"] == "Local alpha"
      assert alpha["completed_count"] == 1
      assert alpha["total_count"] == 1
      assert alpha["refs_count"] == 1
      assert alpha["test_refs_count"] == 0
      assert alpha["has_local_spec"] == true
      assert alpha["has_local_states"] == true
      assert alpha["spec_last_seen_commit"] != nil
      assert alpha["states_inherited"] == false
      assert alpha["refs_inherited"] == false

      assert beta["description"] == "Inherited beta"
      assert beta["completed_count"] == 0
      assert beta["total_count"] == 1
      assert beta["refs_count"] == 0
      assert beta["test_refs_count"] == 1
      assert beta["has_local_spec"] == false
      assert beta["has_local_states"] == false
      assert beta["states_inherited"] == true
      assert beta["refs_inherited"] == true
    end

    # implementation-features.REQUEST.3, implementation-features.REQUEST.3-1, implementation-features.DISCOVERY.6
    test "accepts repeated statuses including null", %{conn: conn, token: token, team: team} do
      ctx = worklist_setup(team)

      spec_fixture(ctx.product, %{
        feature_name: "null-feature",
        branch: ctx.child_branch,
        repo_uri: ctx.child_branch.repo_uri,
        feature_description: "Null status feature",
        requirements: %{
          "null-feature.REQ.1" => %{requirement: "Unset"}
        }
      })

      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get("/api/v1/implementation-features", %{
          "product_name" => ctx.product.name,
          "implementation_name" => ctx.child.name,
          "statuses" => ["null", "completed"]
        })

      assert %{"data" => data} = json_response(conn, 200)
      assert Enum.map(data["features"], & &1["feature_name"]) == ["alpha", "null-feature"]
    end
  end
end
