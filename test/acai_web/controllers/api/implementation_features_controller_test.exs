defmodule AcaiWeb.Api.ImplementationFeaturesControllerTest do
  use AcaiWeb.ConnCase, async: false

  import Acai.DataModelFixtures
  import Acai.AccountsFixtures

  alias Acai.Teams

  describe "GET /api/v1/implementation-features" do
    setup do
      user = user_fixture()
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, token} = Teams.generate_token(%{user: user}, team, %{name: "Read Token"})

      product = product_fixture(team)
      implementation = implementation_fixture(product, %{name: "Production", is_active: true})
      branch = branch_fixture(team, %{repo_uri: "github.com/acai/app", branch_name: "main"})
      tracked_branch_fixture(implementation, %{branch: branch})

      spec =
        spec_fixture(product, %{
          feature_name: "implementation-features-test",
          branch: branch,
          requirements: %{
            "implementation-features-test.REQ.1" => %{requirement: "Do the thing"}
          }
        })

      feature_branch_ref_fixture(branch, spec.feature_name, %{
        refs: %{
          "implementation-features-test.REQ.1" => [
            %{"path" => "lib/acai/example.ex:1", "is_test" => false}
          ]
        }
      })

      %{
        token: token,
        product: product,
        implementation: implementation,
        spec: spec
      }
    end

    test "returns summary features without state filters", %{
      conn: conn,
      token: token,
      product: product,
      implementation: implementation,
      spec: spec
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get(~p"/api/v1/implementation-features",
          product_name: product.name,
          implementation_name: implementation.name
        )

      assert json_response(conn, 200)

      body = Jason.decode!(conn.resp_body)
      [feature] = body["data"]["features"]

      assert feature["feature_name"] == spec.feature_name
      assert feature["refs_count"] == 1
      assert feature["test_refs_count"] == 0
      refute Map.has_key?(feature, "states")
      refute Map.has_key?(feature, "completion")
    end
  end
end
