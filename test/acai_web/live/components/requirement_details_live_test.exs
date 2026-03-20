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
        "requirement" => "Test requirement definition",
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

  # Helper to get refs_by_branch for the component
  # feature-impl-view.INHERITANCE.3: Now returns refs_by_branch directly instead of aggregated_refs
  defp get_refs_by_branch(spec, implementation) do
    {aggregated_refs, _is_inherited} =
      Implementations.get_aggregated_refs_with_inheritance(spec.feature_name, implementation.id)

    # Transform aggregated_refs to refs_by_branch format
    # Same logic as in ImplementationLive.get_refs_by_branch/2
    acid = "#{spec.feature_name}.COMP.1"

    aggregated_refs
    |> Enum.reduce(%{}, fn {branch, refs_map}, acc ->
      case Map.get(refs_map, acid) do
        nil -> acc
        ref_list when is_list(ref_list) -> Map.put(acc, branch, ref_list)
        _ -> acc
      end
    end)
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
          "requirement" => "Test requirement definition",
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

      # feature-impl-view.INHERITANCE.2: Pass pre-resolved states from parent LiveView
      states = %{
        "test-feature.COMP.1" => %{
          "status" => "completed",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true,
        states: states,
        states_inherited: false
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
    test "shows implementation name as context label for local status", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      # feature-impl-view.INHERITANCE.2: Local status shows implementation context
      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true,
        states_inherited: false
      }

      html = render_drawer(assigns)
      assert html =~ implementation.name
    end
  end

  # feature-impl-view.INHERITANCE.2
  describe "feature-impl-view.INHERITANCE.2: Inherited status presentation" do
    setup :register_and_log_in_user

    # feature-impl-view.INHERITANCE.2
    test "shows Inherited badge when states_inherited is true", %{user: user} do
      team = team_fixture()
      product = product_fixture(team)
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      # Create parent implementation (source of inherited status)
      # Preload team for the link in popover
      parent_impl =
        implementation_fixture(product, %{name: "ParentImpl"})
        |> Acai.Repo.preload(:team)

      # Create child implementation that inherits status
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      requirements = %{
        "test-feature.COMP.1" => %{
          "requirement" => "Test requirement",
          "note" => nil,
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      spec = spec_fixture(product, %{feature_name: "test-feature", requirements: requirements})

      # Create spec_impl_state on parent implementation
      spec_impl_state_fixture(spec, parent_impl, %{
        states: %{
          "test-feature.COMP.1" => %{
            "status" => "accepted",
            "comment" => "Inherited comment",
            "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }
      })

      # feature-impl-view.INHERITANCE.2: Pass pre-resolved states from parent LiveView
      states = %{
        "test-feature.COMP.1" => %{
          "status" => "accepted",
          "comment" => "Inherited comment",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: child_impl,
        visible: true,
        states: states,
        states_inherited: true,
        states_source_impl: parent_impl,
        feature_name: "test-feature"
      }

      html = render_drawer(assigns)

      # feature-impl-view.INHERITANCE.2: Should show Inherited badge with stable ID
      # ACID dots are converted to dashes for DOM-safe IDs
      assert html =~ "id=\"drawer-inherited-badge-test-feature-COMP-1\""
      # feature-impl-view.INHERITANCE.2: Should show the inherited status from passed states
      assert html =~ "accepted"

      # feature-impl-view.INHERITANCE.2: Should not show child implementation name (it's inherited, not local)
      refute html =~ child_impl.name
    end

    # feature-impl-view.INHERITANCE.2
    test "inherited badge popover contains source implementation link", %{user: user} do
      team = team_fixture()
      product = product_fixture(team)
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      # Create parent implementation (source of inherited status)
      parent_impl =
        implementation_fixture(product, %{name: "ParentImpl"})
        |> Acai.Repo.preload(:team)

      # Create child implementation
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      requirements = %{
        "test-feature.COMP.1" => %{
          "requirement" => "Test requirement",
          "note" => nil,
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      spec = spec_fixture(product, %{feature_name: "test-feature", requirements: requirements})

      # feature-impl-view.INHERITANCE.2: Pass pre-resolved states from parent LiveView
      states = %{
        "test-feature.COMP.1" => %{
          "status" => "completed",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: child_impl,
        visible: true,
        states: states,
        states_inherited: true,
        states_source_impl: parent_impl,
        feature_name: "test-feature"
      }

      html = render_drawer(assigns)

      # feature-impl-view.INHERITANCE.2: Should show Inherited badge with unique ID and popovertarget
      # ACID dots are converted to dashes for DOM-safe IDs
      assert html =~ "id=\"drawer-inherited-badge-test-feature-COMP-1\""
      assert html =~ "popovertarget=\"drawer-inherited-popover-test-feature-COMP-1\""

      # feature-impl-view.INHERITANCE.2: Popover container should exist with correct ID
      assert html =~ "id=\"drawer-inherited-popover-test-feature-COMP-1\""

      # feature-impl-view.INHERITANCE.2: Popover should contain explanatory copy
      assert html =~ "No states have been added for this implementation"

      # feature-impl-view.INHERITANCE.2: Popover should contain source implementation link wrapper with stable ID
      assert html =~ "id=\"drawer-inherited-source-wrapper\""
      assert html =~ parent_impl.name
    end

    # feature-impl-view.INHERITANCE.2
    test "inherited status comment still renders", %{user: user} do
      team = team_fixture()
      product = product_fixture(team)
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      # Preload team for the link in popover
      parent_impl =
        implementation_fixture(product, %{name: "ParentImpl"})
        |> Acai.Repo.preload(:team)

      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      requirements = %{
        "test-feature.COMP.1" => %{
          "requirement" => "Test requirement",
          "note" => nil,
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      spec = spec_fixture(product, %{feature_name: "test-feature", requirements: requirements})

      # feature-impl-view.INHERITANCE.2: Pass pre-resolved states from parent LiveView
      # Include the comment from the inherited status
      states = %{
        "test-feature.COMP.1" => %{
          "status" => "accepted",
          "comment" => "This status was set on parent implementation",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: child_impl,
        visible: true,
        states: states,
        states_inherited: true,
        states_source_impl: parent_impl,
        feature_name: "test-feature"
      }

      html = render_drawer(assigns)

      # feature-impl-view.INHERITANCE.2: Should show the inherited status comment
      assert html =~ "Status Comment"
      assert html =~ "This status was set on parent implementation"
    end

    # feature-impl-view.INHERITANCE.2
    test "local status does not show inherited badge", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      # Create local state (not inherited)
      # feature-impl-view.INHERITANCE.2: Pass pre-resolved states for local (non-inherited) status
      states = %{
        "test-feature.COMP.1" => %{
          "status" => "completed",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        visible: true,
        states: states,
        states_inherited: false,
        states_source_impl: nil,
        feature_name: "test-feature"
      }

      html = render_drawer(assigns)

      # feature-impl-view.INHERITANCE.2: Should show status from passed states
      assert html =~ "completed"
      # feature-impl-view.INHERITANCE.2: Should NOT show Inherited badge with ID
      # ACID dots are converted to dashes for DOM-safe IDs
      refute html =~ "id=\"drawer-inherited-badge-test-feature-COMP-1\""
      refute html =~ ">Inherited<"
      # feature-impl-view.DRAWER.4-2: Should show implementation context chip for local status
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
      refs_by_branch = get_refs_by_branch(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        refs_by_branch: refs_by_branch,
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

      refs_by_branch = get_refs_by_branch(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        refs_by_branch: refs_by_branch,
        visible: true
      }

      html = render_drawer(assigns)
      assert html =~ "lib/my_app/foo.ex:42"
    end

    # feature-impl-view.DRAWER.5: Each ref renders as clickable link to source file at the specific line
    test "clickable link includes line number anchor", %{user: user} do
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

      refs_by_branch = get_refs_by_branch(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        refs_by_branch: refs_by_branch,
        visible: true
      }

      html = render_drawer(assigns)
      # The link uses the actual branch repo_uri from the database
      # Branch is created by tracked_branch_fixture with default repo_uri
      # feature-impl-view.DRAWER.5: Link should include #L42 line anchor
      assert html =~ "lib/my_app/foo.ex"
      assert html =~ "#L42"
    end

    # feature-impl-view.DRAWER.5: Link works without line number when not present
    test "clickable link works without line number", %{user: user} do
      %{spec: spec, implementation: implementation} = setup_data_chain()
      _role = user_team_role_fixture(team_fixture(), user, %{title: "owner"})

      _spec_impl_ref =
        spec_impl_ref_fixture(spec, implementation, %{
          refs: %{
            "test-feature.COMP.1" => [
              %{
                "path" => "lib/my_app/bar.ex",
                "is_test" => false
              }
            ]
          }
        })

      refs_by_branch = get_refs_by_branch(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        refs_by_branch: refs_by_branch,
        visible: true
      }

      html = render_drawer(assigns)
      # Should show the file path without line anchor
      assert html =~ "lib/my_app/bar.ex"
      # Should not have line anchor since no line number in path
      refute html =~ "#L"
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

      refs_by_branch = get_refs_by_branch(spec, implementation)

      assigns = %{
        id: "test-drawer",
        refs_by_branch: refs_by_branch,
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

  describe "feature-impl-view.DRAWER.4-1: Repository name display in references" do
    setup :register_and_log_in_user

    # feature-impl-view.DRAWER.4-1
    test "repo chip shows repo name for GitHub URIs", %{user: user} do
      team = team_fixture()
      product = product_fixture(team)
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      requirements = %{
        "test-feature.COMP.1" => %{
          "requirement" => "Test requirement",
          "note" => nil,
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      # Create branch with GitHub URI
      branch = branch_fixture(team, %{repo_uri: "github.com/owner/my-repo", branch_name: "main"})

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          requirements: requirements,
          branch: branch
        })

      implementation = implementation_fixture(product, %{name: "Production"})

      # Need to create tracked branch linking implementation to the spec's branch
      tracked_branch_fixture(implementation, branch: branch, repo_uri: branch.repo_uri)

      # Create spec_impl_ref with refs on the GitHub branch
      spec_impl_ref_fixture(spec, implementation, %{
        refs: %{
          "test-feature.COMP.1" => [
            %{
              "path" => "lib/file.ex:10",
              "is_test" => false
            }
          ]
        }
      })

      refs_by_branch = get_refs_by_branch(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        refs_by_branch: refs_by_branch,
        visible: true
      }

      html = render_drawer(assigns)

      # feature-impl-view.DRAWER.4-1: Should show only "my-repo" not the full URI
      assert html =~ "my-repo"
      # Verify the clickable repository popover link is rendered
      assert html =~ "href=\"https://github.com/owner/my-repo\""
    end

    # feature-impl-view.DRAWER.4-1
    test "repo chip shows repo name for GitLab URIs", %{user: user} do
      team = team_fixture()
      product = product_fixture(team)
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      requirements = %{
        "test-feature.COMP.1" => %{
          "requirement" => "Test requirement",
          "note" => nil,
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      # Create branch with GitLab URI
      branch = branch_fixture(team, %{repo_uri: "gitlab.com/group/project", branch_name: "main"})

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          requirements: requirements,
          branch: branch
        })

      implementation = implementation_fixture(product, %{name: "Production"})

      # Need to create tracked branch linking implementation to the spec's branch
      tracked_branch_fixture(implementation, branch: branch, repo_uri: branch.repo_uri)

      spec_impl_ref_fixture(spec, implementation, %{
        refs: %{
          "test-feature.COMP.1" => [
            %{
              "path" => "lib/file.ex:10",
              "is_test" => false
            }
          ]
        }
      })

      refs_by_branch = get_refs_by_branch(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        refs_by_branch: refs_by_branch,
        visible: true
      }

      html = render_drawer(assigns)

      # feature-impl-view.DRAWER.4-1: Should show only "project" not the full URI
      assert html =~ "project"
      # Verify the clickable repository popover link is rendered
      assert html =~ "href=\"https://gitlab.com/group/project\""
    end

    # feature-impl-view.DRAWER.4-1
    test "repo chip shows full repo_uri for unknown patterns", %{user: user} do
      team = team_fixture()
      product = product_fixture(team)
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      requirements = %{
        "test-feature.COMP.1" => %{
          "requirement" => "Test requirement",
          "note" => nil,
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      # Create branch with unknown URI pattern
      unknown_uri = "bitbucket.org/team/project"
      branch = branch_fixture(team, %{repo_uri: unknown_uri, branch_name: "main"})

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          requirements: requirements,
          branch: branch
        })

      implementation = implementation_fixture(product, %{name: "Production"})

      # Need to create tracked branch linking implementation to the spec's branch
      tracked_branch_fixture(implementation, branch: branch, repo_uri: branch.repo_uri)

      spec_impl_ref_fixture(spec, implementation, %{
        refs: %{
          "test-feature.COMP.1" => [
            %{
              "path" => "lib/file.ex:10",
              "is_test" => false
            }
          ]
        }
      })

      refs_by_branch = get_refs_by_branch(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        refs_by_branch: refs_by_branch,
        visible: true
      }

      html = render_drawer(assigns)

      # feature-impl-view.DRAWER.4-1: Unknown patterns should show full URI
      assert html =~ "bitbucket.org/team/project"
    end

    # feature-impl-view.DRAWER.4-1
    # Regression test: hosts that share a prefix with known hosts should NOT be reformatted
    test "repo chip shows full URI for hosts sharing prefix with known hosts", %{user: user} do
      team = team_fixture()
      product = product_fixture(team)
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      requirements = %{
        "test-feature.COMP.1" => %{
          "requirement" => "Test requirement",
          "note" => nil,
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      # Create branch with URI that shares prefix with github.com but is different
      # github.com.au should NOT be treated as github.com
      prefix_uri = "github.com.au/team/repo"
      branch = branch_fixture(team, %{repo_uri: prefix_uri, branch_name: "main"})

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          requirements: requirements,
          branch: branch
        })

      implementation = implementation_fixture(product, %{name: "Production"})

      # Need to create tracked branch linking implementation to the spec's branch
      tracked_branch_fixture(implementation, branch: branch, repo_uri: branch.repo_uri)

      spec_impl_ref_fixture(spec, implementation, %{
        refs: %{
          "test-feature.COMP.1" => [
            %{
              "path" => "lib/file.ex:10",
              "is_test" => false
            }
          ]
        }
      })

      refs_by_branch = get_refs_by_branch(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        refs_by_branch: refs_by_branch,
        visible: true
      }

      html = render_drawer(assigns)

      # feature-impl-view.DRAWER.4-1: Should show the full URI, not just "repo"
      assert html =~ "github.com.au/team/repo"
      # Verify the clickable repository popover link is rendered
      assert html =~ "href=\"https://github.com.au/team/repo\""
    end

    # feature-impl-view.DRAWER.4-1
    # Regression test: gitlab.com.internal should NOT match gitlab.com
    test "repo chip shows full URI for gitlab.com.internal host", %{user: user} do
      team = team_fixture()
      product = product_fixture(team)
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      requirements = %{
        "test-feature.COMP.1" => %{
          "requirement" => "Test requirement",
          "note" => nil,
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      # gitlab.com.internal should NOT be treated as gitlab.com
      prefix_uri = "gitlab.com.internal/group/project"
      branch = branch_fixture(team, %{repo_uri: prefix_uri, branch_name: "main"})

      spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          requirements: requirements,
          branch: branch
        })

      implementation = implementation_fixture(product, %{name: "Production"})

      tracked_branch_fixture(implementation, branch: branch, repo_uri: branch.repo_uri)

      spec_impl_ref_fixture(spec, implementation, %{
        refs: %{
          "test-feature.COMP.1" => [
            %{
              "path" => "lib/file.ex:10",
              "is_test" => false
            }
          ]
        }
      })

      refs_by_branch = get_refs_by_branch(spec, implementation)

      assigns = %{
        id: "test-drawer",
        acid: "test-feature.COMP.1",
        spec: spec,
        implementation: implementation,
        refs_by_branch: refs_by_branch,
        visible: true
      }

      html = render_drawer(assigns)

      # Should show the full URI, not just "project"
      # Verify the clickable repository popover link is rendered
      assert html =~ "href=\"https://gitlab.com.internal/group/project\""
    end
  end
end
