defmodule AcaiWeb.FeatureLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.DataModelFixtures

  defp setup_feature_graph(user) do
    team = team_fixture()
    user_team_role_fixture(team, user, %{title: "owner"})

    product = product_fixture(team)
    implementation = implementation_fixture(product, %{name: "Production", is_active: true})
    branch = branch_fixture(team, %{repo_uri: "github.com/acai/app", branch_name: "main"})
    tracked_branch_fixture(implementation, %{branch: branch})

    spec =
      spec_fixture(product, %{
        feature_name: "feature-live-test",
        branch: branch,
        requirements: %{
          "feature-live-test.REQ.1" => %{requirement: "Do the thing"}
        }
      })

    {team, product, implementation, spec}
  end

  describe "mount" do
    setup :register_and_log_in_user

    test "renders feature page without state controls", %{conn: conn, user: user} do
      {team, _product, _implementation, spec} = setup_feature_graph(user)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/#{spec.feature_name}")

      assert has_element?(view, "#implementations-grid")
      refute has_element?(view, "[phx-click='open_status_dropdown']")
      refute has_element?(view, "[phx-click='status_cell_clicked']")
    end
  end
end
