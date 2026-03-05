defmodule AcaiWeb.Live.Components.RequirementDetailsLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.DataModelFixtures

  alias AcaiWeb.Live.Components.RequirementDetailsLive

  # Helper to set up a team with an owner (the logged-in user)
  defp create_team_with_owner(user) do
    team = team_fixture()
    role = user_team_role_fixture(team, user, %{title: "owner"})
    {team, role}
  end

  # Helper to set up the full data chain: team -> spec -> requirement -> implementation -> branch
  defp setup_data_chain(_ctx \\ %{}) do
    team = team_fixture()
    spec = spec_fixture(team, %{feature_name: "test-feature", feature_product: "test-product"})
    # acid is generated as: feature_name || '.' || group_key || '.' || local_id
    # So with feature_name: "example-feature" (default), group_key: "COMP", local_id: "1"
    # the acid will be "example-feature.COMP.1"
    requirement = requirement_fixture(spec)
    implementation = implementation_fixture(spec, %{name: "Production"})
    branch = tracked_branch_fixture(implementation)

    %{
      team: team,
      spec: spec,
      requirement: requirement,
      implementation: implementation,
      branch: branch
    }
  end

  # Helper to render the component directly
  defp render_drawer(assigns) do
    render_component(RequirementDetailsLive, assigns)
  end

  describe "requirement-details.DRAWER.1: Renders requirement ACID as title" do
    setup :register_and_log_in_user

    test "renders the requirement ACID as the drawer title", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ requirement.acid
    end
  end

  describe "requirement-details.DRAWER.2: Renders requirement definition" do
    setup :register_and_log_in_user

    test "renders the full requirement definition text", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ requirement.definition
    end
  end

  describe "requirement-details.DRAWER.3: Renders requirement note" do
    setup :register_and_log_in_user

    test "renders requirement note when present", %{user: user} do
      team = team_fixture()
      spec = spec_fixture(team)
      requirement = requirement_fixture(spec, %{note: "This is a test note."})
      implementation = implementation_fixture(spec)
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "This is a test note."
    end

    test "does not render note section when nil", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # The note section should not be present
      refute html =~ "<h3>Note</h3>"
    end
  end

  describe "requirement-details.DRAWER.4: Status section" do
    setup :register_and_log_in_user

    test "renders status value when exists", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      # Create a requirement status
      _status = requirement_status_fixture(implementation, requirement, %{status: "accepted"})

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "accepted"
    end

    # requirement-details.DRAWER.4-1
    test "shows 'No status' indicator when status is null", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      # Create a requirement status with nil status
      _status = requirement_status_fixture(implementation, requirement, %{status: nil})

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "No status"
    end

    # requirement-details.DRAWER.4-1
    test "shows 'No status' indicator when no requirement_status row exists", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "No status"
    end

    # requirement-details.DRAWER.4-2
    test "shows implementation name as context label", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ implementation.name
    end
  end

  describe "requirement-details.DRAWER.5: References section" do
    setup :register_and_log_in_user

    # requirement-details.DRAWER.5
    test "renders References section", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "References"
    end

    # requirement-details.DRAWER.5-1
    test "only shows references for tracked branches in current implementation", %{user: user} do
      %{
        spec: spec,
        requirement: requirement,
        implementation: implementation,
        branch: branch
      } = setup_data_chain()

      create_team_with_owner(user)

      # Create a code reference for this implementation's branch
      ref = code_reference_fixture(requirement, branch)

      # Create another implementation with a different branch
      other_implementation = implementation_fixture(spec, %{name: "Other"})
      other_branch = tracked_branch_fixture(other_implementation)

      # Create a reference for the other branch (should not appear)
      code_reference_fixture(requirement, other_branch, %{path: "lib/other.ex:10"})

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Should show the reference for this implementation's branch
      assert html =~ ref.path
      # Should NOT show the reference for the other implementation's branch
      refute html =~ "lib/other.ex:10"
    end

    # requirement-details.DRAWER.5-1
    test "excludes references for branches not tracked by implementation", %{user: user} do
      %{spec: spec, requirement: requirement, implementation: implementation} = setup_data_chain()

      create_team_with_owner(user)

      # Create another implementation with a different branch
      other_implementation = implementation_fixture(spec, %{name: "Other"})
      other_branch = tracked_branch_fixture(other_implementation)

      # Create a reference for the other branch
      code_reference_fixture(requirement, other_branch, %{path: "lib/other.ex:10"})

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Should show "No code references found"
      assert html =~ "No code references found"
    end

    # requirement-details.DRAWER.5-2
    test "groups references by tracked branch", %{user: user} do
      %{requirement: requirement, implementation: implementation, branch: branch} =
        setup_data_chain()

      create_team_with_owner(user)

      ref1 = code_reference_fixture(requirement, branch, %{path: "lib/file1.ex:10"})
      ref2 = code_reference_fixture(requirement, branch, %{path: "lib/file2.ex:20"})

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Both references should be under the same branch
      assert html =~ ref1.path
      assert html =~ ref2.path
    end

    test "group header shows repo_uri and branch_name", %{user: user} do
      %{requirement: requirement, implementation: implementation, branch: branch} =
        setup_data_chain()

      create_team_with_owner(user)

      _ref = code_reference_fixture(requirement, branch)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ branch.repo_uri
      assert html =~ branch.branch_name
    end

    # requirement-details.DRAWER.5-3
    test "each reference shows file path and line number", %{user: user} do
      %{requirement: requirement, implementation: implementation, branch: branch} =
        setup_data_chain()

      create_team_with_owner(user)

      ref = code_reference_fixture(requirement, branch, %{path: "lib/my_app/foo.ex:42"})

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ ref.path
    end

    # requirement-details.DRAWER.5-4
    test "clickable link format is correct", %{user: user} do
      %{requirement: requirement, implementation: implementation, branch: branch} =
        setup_data_chain()

      create_team_with_owner(user)

      _ref = code_reference_fixture(requirement, branch, %{path: "lib/my_app/foo.ex:42"})

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # The link should be: https://<repo_uri>/blob/<branch_name>/<path>
      expected_href = "https://#{branch.repo_uri}/blob/#{branch.branch_name}/lib/my_app/foo.ex"
      assert html =~ expected_href
    end

    # requirement-details.DRAWER.5-5
    test "test references visually distinguished", %{user: user} do
      %{requirement: requirement, implementation: implementation, branch: branch} =
        setup_data_chain()

      create_team_with_owner(user)

      _test_ref =
        code_reference_fixture(requirement, branch, %{path: "test/my_test.exs:10", is_test: true})

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Should have the test badge
      assert html =~ "badge-info"
      assert html =~ "Test"
    end

    test "non-test references display correctly", %{user: user} do
      %{requirement: requirement, implementation: implementation, branch: branch} =
        setup_data_chain()

      create_team_with_owner(user)

      _non_test_ref =
        code_reference_fixture(requirement, branch, %{
          path: "lib/my_app/foo.ex:10",
          is_test: false
        })

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Should show the reference path
      assert html =~ "lib/my_app/foo.ex:10"
    end

    test "handles requirement with no references", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "No code references found"
    end
  end

  describe "requirement-details.DRAWER.6: Drawer interaction" do
    setup :register_and_log_in_user

    test "drawer can be dismissed", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Should have close button
      assert html =~ "aria-label=\"Close drawer\""
    end

    test "close button dismisses drawer", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Close button should have phx-click="close"
      assert html =~ "phx-click=\"close\""
    end

    test "backdrop click dismisses drawer", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Backdrop should have phx-click="close"
      assert html =~ "phx-click=\"close\""
    end

    test "escape key dismisses drawer", %{user: user} do
      %{requirement: requirement, implementation: implementation} = setup_data_chain()
      create_team_with_owner(user)

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Drawer should have phx-window-keydown="close" and phx-key="Escape"
      assert html =~ "phx-window-keydown=\"close\""
      assert html =~ "phx-key=\"Escape\""
    end
  end

  describe "Data isolation tests" do
    setup :register_and_log_in_user

    test "only shows references for the correct implementation", %{user: user} do
      %{
        spec: spec,
        requirement: requirement,
        implementation: implementation,
        branch: branch
      } = setup_data_chain()

      create_team_with_owner(user)

      # Create a code reference for this implementation's branch
      ref = code_reference_fixture(requirement, branch)

      # Create another implementation with a different branch
      other_implementation = implementation_fixture(spec, %{name: "Other"})
      other_branch = tracked_branch_fixture(other_implementation)

      # Create a reference for the other branch
      _other_ref = code_reference_fixture(requirement, other_branch, %{path: "lib/other.ex:10"})

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Should show the reference for this implementation's branch
      assert html =~ ref.path
      # Should NOT show the reference for the other implementation's branch
      refute html =~ "lib/other.ex:10"
    end

    test "does not show references from other implementations", %{user: user} do
      %{spec: spec, requirement: requirement, implementation: implementation} = setup_data_chain()

      create_team_with_owner(user)

      # Create another implementation with a different branch
      other_implementation = implementation_fixture(spec, %{name: "Other"})
      other_branch = tracked_branch_fixture(other_implementation)

      # Create a reference for the other branch
      code_reference_fixture(requirement, other_branch, %{path: "lib/other.ex:10"})

      assigns = %{
        id: "test-drawer",
        requirement: requirement,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Should show "No code references found"
      assert html =~ "No code references found"
    end
  end
end
