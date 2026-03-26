defmodule AcaiWeb.ImplementationLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.DataModelFixtures

  alias Acai.Implementations

  defp setup_feature_graph(user) do
    team = team_fixture()
    user_team_role_fixture(team, user, %{title: "owner"})

    product = product_fixture(team)
    implementation = implementation_fixture(product, %{name: "Production", is_active: true})
    branch = branch_fixture(team, %{repo_uri: "github.com/acai/app", branch_name: "main"})
    tracked_branch_fixture(implementation, %{branch: branch})

    spec =
      spec_fixture(product, %{
        feature_name: "implementation-live-test",
        branch: branch,
        requirements: %{
          "implementation-live-test.REQ.1" => %{requirement: "Do the thing"}
        }
      })

    {team, product, implementation, spec}
  end

  describe "mount" do
    setup :register_and_log_in_user

    test "renders refs-only implementation page without status controls", %{
      conn: conn,
      user: user
    } do
      {team, _product, implementation, spec} = setup_feature_graph(user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/t/#{team.name}/i/#{Implementations.implementation_slug(implementation)}/f/#{spec.feature_name}"
        )

      assert has_element?(view, "#requirements-table-container")
      assert has_element?(view, "#sort-requirements-acid")
      assert has_element?(view, "#sort-requirements-requirement")
      assert has_element?(view, "#sort-requirements-refs-count")
      assert has_element?(view, "#test-coverage-grid")
      refute has_element?(view, "#sort-requirements-status")
      refute has_element?(view, "#requirements-coverage-grid")
      refute has_element?(view, "[phx-click='open_status_dropdown']")
      refute has_element?(view, "[phx-click='status_cell_clicked']")
    end
  end
end
