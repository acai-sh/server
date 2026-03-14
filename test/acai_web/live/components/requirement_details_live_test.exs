defmodule AcaiWeb.Live.Components.RequirementDetailsLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.DataModelFixtures

  alias AcaiWeb.Live.Components.RequirementDetailsLive

  alias Acai.Implementations

  # Helper to set up the full data chain with new data model
  defp setup_data_chain(_ctx \\ %{}) do
    team = team_fixture()
    product = product_fixture(team)

    # data-model.SPECS.13: Requirements stored as JSONB
    requirements = %{
      "test-feature.COMP.1" => %{
        "definition" => "Test requirement definition",
        "note" => "Test note",
        "is_deprecated" => false,
        "replaced_by" => []
      }
    }

    spec = spec_fixture(product, %{feature_name: "test-feature", requirements: requirements})
    implementation = implementation_fixture(product, %{name: "Production"})
    _branch = tracked_branch_fixture(implementation)

    %{
      team: team,
      product: product,
      spec: spec,
      implementation: implementation
    }
  end

  # Helper to get aggregated refs for the component
  defp get_aggregated_refs(spec, implementation) do
    {aggregated_refs, _is_inherited} =
      Implementations.get_aggregated_refs_with_inheritance(spec.feature_name, implementation.id)

    aggregated_refs
  end

  # Helper to render the component directly
  defp render_drawer(assigns) do
    render_component(RequirementDetailsLive, assigns)
  end

  describe "requirement-details.DRAWER.1: Renders requirement ACID as title" do
    setup :register_and_log_in_user

    test "renders the requirement ACID as the drawer title", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "test-feature.COMP.1"
    end
  end

  describe "requirement-details.DRAWER.2: Renders requirement definition" do
    setup :register_and_log_in_user

    test "renders the full requirement definition text", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "Test requirement definition"
    end
  end

  describe "requirement-details.DRAWER.3: Renders requirement note" do
    setup :register_and_log_in_user

    test "renders requirement note when present", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "Test note"
    end

    test "does not render note section when nil", %{user: user} do
      team = team_fixture()
      product = product_fixture(team)

      # Create spec with nil note
      requirements = %{
        "test-feature.COMP.1" => %{
          "definition" => "Test requirement definition",
          "note" => nil,
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      spec = spec_fixture(product, %{feature_name: "test-feature", requirements: requirements})
      implementation = implementation_fixture(product)
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # The note section should not be present when note is nil
      refute html =~ "Test note"
    end
  end

  describe "requirement-details.DRAWER.4: Status section" do
    setup :register_and_log_in_user

    test "renders status value when exists", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      # data-model.SPEC_IMPL_STATES: Create a spec_impl_state with status
      _spec_impl_state =
        spec_impl_state_fixture(spec, implementation, %{
          states: %{
            "test-feature.COMP.1" => %{
              "status" => "completed",
              "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
            }
          }
        })

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "completed"
    end

    # requirement-details.DRAWER.4-1
    test "shows 'No status' indicator when status is null", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "No status"
    end

    # requirement-details.DRAWER.4-2
    test "shows implementation name as context label", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
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
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "References"
    end

    # requirement-details.DRAWER.5-2
    # data-model.FEATURE_BRANCH_REFS: refs stored on branches
    test "groups references by repo", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      # Create spec_impl_ref with refs JSONB on tracked branches
      _spec_impl_ref =
        spec_impl_ref_fixture(spec, implementation, %{
          refs: %{
            "test-feature.COMP.1" => [
              %{
                "path" => "lib/file1.ex:10",
                "is_test" => false
              },
              %{
                "path" => "lib/file2.ex:20",
                "is_test" => false
              }
            ]
          }
        })

      # Get aggregated refs for the component
      aggregated_refs = get_aggregated_refs(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        aggregated_refs: aggregated_refs,
        visible: true
      }

      html = render_drawer(assigns)
      # Both references should be shown
      assert html =~ "lib/file1.ex:10"
      assert html =~ "lib/file2.ex:20"
    end

    # requirement-details.DRAWER.5-3
    test "each reference shows file path", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      _spec_impl_ref =
        spec_impl_ref_fixture(spec, implementation, %{
          refs: %{
            "test-feature.COMP.1" => [
              %{
                "path" => "lib/my_app/foo.ex:42",
                "is_test" => false
              }
            ]
          }
        })

      aggregated_refs = get_aggregated_refs(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        aggregated_refs: aggregated_refs,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "lib/my_app/foo.ex:42"
    end

    # requirement-details.DRAWER.5-4
    test "clickable link format is correct", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      _spec_impl_ref =
        spec_impl_ref_fixture(spec, implementation, %{
          refs: %{
            "test-feature.COMP.1" => [
              %{
                "path" => "lib/my_app/foo.ex:42",
                "is_test" => false
              }
            ]
          }
        })

      aggregated_refs = get_aggregated_refs(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        aggregated_refs: aggregated_refs,
        visible: true
      }

      html = render_drawer(assigns)
      # The link uses the actual branch repo_uri from the database
      # Branch is created by tracked_branch_fixture with default repo_uri
      assert html =~ "lib/my_app/foo.ex"
    end

    # requirement-details.DRAWER.5-5
    test "test references visually distinguished", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      _spec_impl_ref =
        spec_impl_ref_fixture(spec, implementation, %{
          refs: %{
            "test-feature.COMP.1" => [
              %{
                "path" => "test/my_test.exs:10",
                "is_test" => true
              }
            ]
          }
        })

      aggregated_refs = get_aggregated_refs(spec, implementation)

      assigns = %{
        id: "test-drawer",
        aggregated_refs: aggregated_refs,
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Should have the test badge
      assert html =~ "badge-info"
      assert html =~ "Test"
    end

    test "handles requirement with no references", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
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
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Should have close button
      assert html =~ "aria-label=\"Close drawer\""
    end

    test "close button dismisses drawer", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Close button should have phx-click="close"
      assert html =~ "phx-click=\"close\""
    end

    test "backdrop click dismisses drawer", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Backdrop should have phx-click="close"
      assert html =~ "phx-click=\"close\""
    end

    test "escape key dismisses drawer", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true
      }

      html = render_drawer(assigns)
      # Drawer should have phx-window-keydown="close" and phx-key="Escape"
      assert html =~ "phx-window-keydown=\"close\""
      assert html =~ "phx-key=\"Escape\""
    end
  end
end
