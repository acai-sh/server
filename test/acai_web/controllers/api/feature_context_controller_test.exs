defmodule AcaiWeb.Api.FeatureContextControllerTest do
  use AcaiWeb.ConnCase, async: false

  import Acai.DataModelFixtures
  import Acai.AccountsFixtures

  alias Acai.Teams

  describe "GET /api/v1/feature-context" do
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
          feature_name: "feature-context-test",
          branch: branch,
          requirements: %{
            "feature-context-test.REQ.1" => %{requirement: "Do the thing"}
          }
        })

      feature_branch_ref_fixture(branch, spec.feature_name, %{
        refs: %{
          "feature-context-test.REQ.1" => [
            %{"path" => "lib/acai/example.ex:1", "is_test" => false}
          ]
        }
      })

      %{
        token: token,
        team: team,
        product: product,
        implementation: implementation,
        spec: spec
      }
    end

    test "returns canonical requirements and refs without state filters", %{
      conn: conn,
      token: token,
      product: product,
      implementation: implementation,
      spec: spec
    } do
      conn =
        conn
        |> put_req_header("authorization", "Bearer #{token.raw_token}")
        |> get(~p"/api/v1/feature-context",
          product_name: product.name,
          feature_name: spec.feature_name,
          implementation_name: implementation.name,
          include_refs: true
        )

      assert json_response(conn, 200)

      body = Jason.decode!(conn.resp_body)
      data = body["data"]

      assert data["product_name"] == product.name
      assert data["feature_name"] == spec.feature_name
      assert data["implementation_name"] == implementation.name
      refute Map.has_key?(data, "states")
      assert [%{"acid" => "feature-context-test.REQ.1"}] = data["acids"]
      assert data["acids"] |> List.first() |> Map.get("refs_count") == 1
    end
  end
end
