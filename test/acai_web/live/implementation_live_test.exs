defmodule AcaiWeb.ImplementationLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.AccountsFixtures
  import Acai.DataModelFixtures

  alias Acai.Implementations

  # Helper to set up a team with an owner (the logged-in user)
  defp create_team_with_owner(user) do
    team = team_fixture()
    role = user_team_role_fixture(team, user, %{title: "owner"})
    {team, role}
  end

  # data-model.PRODUCTS: Create product as first-class entity
  defp create_product(team, name) do
    product_fixture(team, %{name: name, is_active: true})
  end

  # data-model.SPECS: Create spec for a product with JSONB requirements
  # feature-impl-view.INHERITANCE.1: Spec must be on a tracked branch for canonical resolution
  defp create_spec_for_feature(team, product, feature_name, opts \\ []) do
    unique_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    implementation = Keyword.get(opts, :for_implementation)

    # data-model.SPECS.11: Requirements stored as JSONB keyed by ACID
    requirements =
      Keyword.get(opts, :requirements, %{
        "#{feature_name}.COMP.1" => %{
          "definition" => "Test requirement 1 for #{feature_name}",
          "note" => "Test note",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "#{feature_name}.COMP.2" => %{
          "definition" => "Test requirement 2 for #{feature_name}",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      })

    # Create a branch for the spec (will be used as tracked branch)
    branch = branch_fixture(team)

    # Use provided implementation, or find/create one for tracked branch
    impl =
      case implementation do
        nil ->
          # Check if there are existing implementations in this product
          case Acai.Implementations.list_implementations(product) do
            [] -> implementation_fixture(product, %{name: "TestImpl", is_active: true})
            [existing | _] -> existing
          end

        impl ->
          impl
      end

    # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch for canonical resolution
    # Create tracked branch linking implementation to spec's branch
    tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

    spec_fixture(product, %{
      feature_name: feature_name,
      feature_description: Keyword.get(opts, :description, "Description for #{feature_name}"),
      path: "features/#{feature_name}-#{unique_suffix}/feature.yaml",
      repo_uri: "github.com/test/repo-#{unique_suffix}",
      branch: branch,
      requirements: requirements
    })
  end

  # data-model.IMPLS: Create implementation for a product
  defp create_implementation_for_product(product, opts \\ []) do
    implementation_fixture(product, %{
      name: Keyword.get(opts, :name, "Impl-#{System.unique_integer([:positive])}"),
      is_active: Keyword.get(opts, :is_active, true)
    })
  end

  # data-model.FEATURE_IMPL_STATES: Create feature_impl_state with JSONB states
  defp create_spec_impl_state(spec, implementation, opts) do
    acid_prefix = spec.feature_name <> ".COMP"

    states =
      Keyword.get(opts, :states, %{
        "#{acid_prefix}.1" => %{
          "status" => Keyword.get(opts, :status, "pending"),
          "comment" => "Test comment",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      })

    spec_impl_state_fixture(spec, implementation, %{states: states})
  end

  # data-model.FEATURE_BRANCH_REFS: Create feature_branch_ref with JSONB refs
  # Uses new format: refs keyed by ACID with path and is_test only
  defp create_spec_impl_ref(spec, implementation, opts) do
    acid_prefix = spec.feature_name <> ".COMP"

    # Convert old format refs to new format (path only, no repo/loc)
    refs =
      Keyword.get(opts, :refs, %{
        "#{acid_prefix}.1" => [
          %{
            "path" => Keyword.get(opts, :path, "lib/my_app/my_module.ex:42"),
            "is_test" => Keyword.get(opts, :is_test, false)
          }
        ]
      })
      |> Enum.map(fn {acid, ref_list} ->
        new_refs =
          Enum.map(ref_list, fn ref ->
            %{
              "path" => ref["path"] || "lib/default.ex:1",
              "is_test" => ref["is_test"] || false
            }
          end)

        {acid, new_refs}
      end)
      |> Map.new()

    spec_impl_ref_fixture(spec, implementation, %{refs: refs})
  end

  # Helper to build slug for an implementation
  defp build_impl_slug(impl) do
    Implementations.implementation_slug(impl)
  end

  describe "unauthenticated access" do
    test "redirects to log-in", %{conn: conn} do
      team = team_fixture()
      # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format with dash separator
      slug = "some-impl-018f1a2b3c4d5e6f7a8b9c0d1e2f3a4b"

      {:error, {:redirect, %{to: path}}} =
        live(conn, ~p"/t/#{team.name}/i/#{slug}/f/some-feature")

      assert path == ~p"/users/log-in"
    end
  end

  describe "mount" do
    setup :register_and_log_in_user

    # feature-impl-view.CARDS.1: Renders interactive title header with implementation dropdown
    test "renders the implementation name in dropdown", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")
      # Check that implementation dropdown button exists with the correct value
      assert has_element?(view, "button[popovertarget='impl-popover']", "Production")
    end

    # implementation-view.MAIN.2
    test "renders breadcrumb with overview, product, and feature links", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Check breadcrumb links exist (home icon for overview, then product and feature)
      assert has_element?(view, "a[href='/t/#{team.name}'] span.hero-home")
      assert has_element?(view, "a[href='/t/#{team.name}/p/MyProduct']", "MyProduct")
      assert has_element?(view, "a[href='/t/#{team.name}/f/my-feature']", "my-feature")
    end

    # implementation-view.ROUTING.2
    test "parses slug and finds implementation by UUID", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")
      # Verify implementation was found by checking dropdown button has the right value
      assert has_element?(view, "button[popovertarget='impl-popover']", "Production")
    end

    # implementation-view.ROUTING.2-1
    # feature-impl-view.ROUTING.2: impl_name is sanitized and trimmed for URL safety (cosmetic)
    test "slug name portion is cosmetic and ignored", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      # Build slug with wrong name but correct UUID
      # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format with dash separator
      uuid_string = impl.id |> to_string()
      uuid_without_dashes = String.replace(uuid_string, "-", "")
      wrong_name_slug = "wrong-name-#{uuid_without_dashes}"

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{wrong_name_slug}/f/my-feature")
      # Should still show the correct implementation name in dropdown button
      assert has_element?(view, "button[popovertarget='impl-popover']", "Production")
    end

    test "uses URL-safe slug when implementation name has special characters", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      # Create implementation with special name first
      impl = create_implementation_for_product(product, name: "QA / Canary + EU-West 🚀")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      slug = build_impl_slug(impl)

      # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format with dash separator
      assert slug =~ ~r/^[a-z0-9-]+-[0-9a-f]{32}$/

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")
      # Verify implementation name appears in dropdown button
      assert has_element?(view, "button[popovertarget='impl-popover']", "QA / Canary + EU-West 🚀")
    end

    # implementation-view.ROUTING.3
    test "redirects to feature view if implementation not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")

      # Use a non-existent UUID
      # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format with dash separator
      fake_slug = "some-impl-018f1a2b3c4d5e6f7a8b9c0d1e2f3a4b"

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/t/#{team.name}/i/#{fake_slug}/f/my-feature")

      assert redirect_to == ~p"/t/#{team.name}/f/my-feature"
    end

    # implementation-view.ROUTING.3
    test "shows flash message when implementation not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")

      # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format with dash separator
      fake_slug = "some-impl-018f1a2b3c4d5e6f7a8b9c0d1e2f3a4b"

      assert {:error, {:live_redirect, %{flash: flash}}} =
               live(conn, ~p"/t/#{team.name}/i/#{fake_slug}/f/my-feature")

      assert flash["error"] == "Implementation not found"
    end
  end

  describe "REQ_COVERAGE - requirements coverage grid" do
    setup :register_and_log_in_user

    # implementation-view.REQ_COVERAGE.1
    test "renders one chip per requirement ordered by ACID", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      _spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Should have chips for all requirements
      assert has_element?(view, "div[title='my-feature.COMP.1']")
      assert has_element?(view, "div[title='my-feature.COMP.2']")
    end

    # implementation-view.REQ_COVERAGE.2-1
    # data-model.FEATURE_IMPL_STATES.4-3: accepted (green)
    test "green chip for accepted status", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      create_spec_impl_state(spec, impl, status: "accepted")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, ".bg-success[title='my-feature.COMP.1']")
    end

    # implementation-view.REQ_COVERAGE.2-2
    # data-model.FEATURE_IMPL_STATES.4-3: completed (blue)
    test "blue chip for completed status", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      create_spec_impl_state(spec, impl, status: "completed")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, ".bg-info[title='my-feature.COMP.1']")
    end

    # implementation-view.REQ_COVERAGE.2-3
    test "gray chip for null status", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      # No status created

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, ".bg-base-300[title='my-feature.COMP.1']")
    end

    # implementation-view.REQ_COVERAGE.3
    test "clicking chip opens requirement details drawer", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Click on the chip using the phx-click event (using acid instead of requirement_id)
      view |> render_click("open_drawer", %{"acid" => "my-feature.COMP.1"})

      # Drawer should be visible
      assert has_element?(view, "#requirement-details-drawer")
    end
  end

  describe "TEST_COVERAGE - test coverage grid" do
    setup :register_and_log_in_user

    # implementation-view.TEST_COVERAGE.1
    # data-model.FEATURE_BRANCH_REFS: refs stored as JSONB
    test "renders one chip per requirement ordered by ACID", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      # Add test references via spec_impl_refs
      create_spec_impl_ref(spec, impl,
        refs: %{
          "my-feature.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "test/file_test.ex:1",
              "loc" => "1:1",
              "is_test" => true
            }
          ],
          "my-feature.COMP.2" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "test/file2_test.ex:1",
              "loc" => "1:1",
              "is_test" => true
            }
          ]
        }
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, "div[title*='my-feature.COMP.1']")
      assert has_element?(view, "div[title*='my-feature.COMP.2']")
    end

    # implementation-view.TEST_COVERAGE.2-1
    test "green chip when test references exist", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      # Add test reference via spec_impl_refs
      create_spec_impl_ref(spec, impl,
        refs: %{
          "my-feature.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "test/file_test.ex:1",
              "loc" => "1:1",
              "is_test" => true
            }
          ]
        }
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Should have green background for test coverage
      assert has_element?(view, ".bg-success[title*='my-feature.COMP.1']")
    end

    # implementation-view.TEST_COVERAGE.2-2
    test "gray chip when no test references", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      # Add non-test reference only via spec_impl_refs
      create_spec_impl_ref(spec, impl,
        refs: %{
          "my-feature.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "lib/file.ex:1",
              "loc" => "1:1",
              "is_test" => false
            }
          ]
        }
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Should have gray background for no test coverage
      assert has_element?(view, ".bg-base-300[title*='my-feature.COMP.1']")
    end

    # implementation-view.TEST_COVERAGE.3
    test "displays count of test references on green chips", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      # Add multiple test references
      create_spec_impl_ref(spec, impl,
        refs: %{
          "my-feature.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "test1.ex:1",
              "loc" => "1:1",
              "is_test" => true
            },
            %{
              "repo" => "github.com/org/repo",
              "path" => "test2.ex:2",
              "loc" => "2:1",
              "is_test" => true
            },
            %{
              "repo" => "github.com/org/repo",
              "path" => "test3.ex:3",
              "loc" => "3:1",
              "is_test" => true
            }
          ]
        }
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Should show count 3 inside the chip
      assert has_element?(view, ".bg-success", "3")
    end

    # implementation-view.TEST_COVERAGE.4
    test "clicking chip opens requirement details drawer", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      create_spec_impl_ref(spec, impl,
        refs: %{
          "my-feature.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "test1.ex:1",
              "loc" => "1:1",
              "is_test" => true
            }
          ]
        }
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Click on the test coverage chip using the phx-click event (using acid)
      view |> render_click("open_drawer", %{"acid" => "my-feature.COMP.1"})

      # Drawer should be visible
      assert has_element?(view, "#requirement-details-drawer")
    end
  end

  describe "CANONICAL_SPEC - canonical spec link" do
    setup :register_and_log_in_user

    # implementation-view.CANONICAL_SPEC.1
    test "renders feature name as link to feature view", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, "a[href='/t/#{team.name}/f/my-feature']", "my-feature")
    end
  end

  describe "LINKED_BRANCHES - tracked branches list" do
    setup :register_and_log_in_user

    # implementation-view.LINKED_BRANCHES.1
    test "renders list of tracked branches", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      # create_spec_for_feature already creates a tracked branch, so we add one more
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo2", branch_name: "develop")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, "div", "develop")
    end

    # implementation-view.LINKED_BRANCHES.2
    test "each entry shows repo_uri and branch_name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)

      # Create tracked branch directly with known values
      tracked_branch =
        tracked_branch_fixture(impl,
          repo_uri: "github.com/org/test-repo",
          branch_name: "feature-branch"
        )

      # Load the branch for the spec
      branch = Acai.Repo.get!(Acai.Implementations.Branch, tracked_branch.branch_id)

      # Create spec on that branch
      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Now shows only repo name for known patterns (GitHub)
      assert has_element?(view, "div", "test-repo")
      assert has_element?(view, "div", "feature-branch")
    end

    test "shows empty state when no tracked branches", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create a parent implementation with tracked branch and spec
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      parent_tracked_branch =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      # Load the branch for the spec
      parent_branch = Acai.Repo.get!(Acai.Implementations.Branch, parent_tracked_branch.branch_id)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: parent_branch,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create child implementation without tracked branches - will inherit spec from parent
      impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, "div", "No tracked branches")
    end
  end

  describe "REQ_LIST - requirements table" do
    setup :register_and_log_in_user

    # feature-impl-view.LIST.1: Renders requirements list
    # feature-impl-view.LIST.2: Table columns are ACID, Status, Definition, Refs count
    # feature-impl-view.LIST.2-2
    test "renders table with correct columns", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      _spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Check table headers - 4 columns only per spec
      assert has_element?(view, "th", "ACID")
      assert has_element?(view, "th", "Status")
      assert has_element?(view, "th", "Definition")
      assert has_element?(view, "th", "Refs")
      assert has_element?(view, "#sort-requirements-acid")
      assert has_element?(view, "#sort-requirements-status")
      assert has_element?(view, "#sort-requirements-definition")
      assert has_element?(view, "#sort-requirements-refs-count")
      # Tests column removed per feature-impl-view.LIST.2
      refute has_element?(view, "th", "Tests")

      # Check row content
      assert has_element?(view, "td", "my-feature.COMP.1")
      assert has_element?(view, "td", "Test requirement 1 for my-feature")

      # Check table has stable DOM ID
      assert has_element?(view, "#requirements-list-table")
    end

    # feature-impl-view.LIST.2-2
    # feature-impl-view.LIST.2-3
    test "sorting the table updates the row order and both coverage grids", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)

      spec =
        create_spec_for_feature(team, product, "sort-feature",
          for_implementation: impl,
          requirements: %{
            "sort-feature.COMP.1" => %{
              "definition" => "Zulu requirement",
              "is_deprecated" => false,
              "replaced_by" => []
            },
            "sort-feature.COMP.2" => %{
              "definition" => "Omega requirement",
              "is_deprecated" => false,
              "replaced_by" => []
            },
            "sort-feature.COMP.3" => %{
              "definition" => "Alpha requirement",
              "is_deprecated" => false,
              "replaced_by" => []
            }
          }
        )

      create_spec_impl_ref(spec, impl,
        refs: %{
          "sort-feature.COMP.1" => [
            %{"path" => "lib/one.ex:1", "is_test" => false},
            %{"path" => "test/one_test.exs:1", "is_test" => true}
          ],
          "sort-feature.COMP.2" => [
            %{"path" => "lib/two.ex:1", "is_test" => false}
          ],
          "sort-feature.COMP.3" => [
            %{"path" => "lib/three.ex:1", "is_test" => false},
            %{"path" => "lib/three_extra.ex:2", "is_test" => false},
            %{"path" => "test/three_test.exs:3", "is_test" => true}
          ]
        }
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/sort-feature")

      assert has_element?(
               view,
               "#requirements-list-table tbody tr:nth-child(1) td:nth-child(1)",
               "sort-feature.COMP.1"
             )

      assert has_element?(
               view,
               "#requirements-coverage-grid > a:nth-child(1)[data-acid='sort-feature.COMP.1']"
             )

      assert has_element?(
               view,
               "#test-coverage-grid > a:nth-child(1)[data-acid='sort-feature.COMP.1']"
             )

      view
      |> element("#sort-requirements-definition")
      |> render_click()

      assert has_element?(
               view,
               "#requirements-list-table tbody tr:nth-child(1) td:nth-child(1)",
               "sort-feature.COMP.3"
             )

      assert has_element?(
               view,
               "#requirements-coverage-grid > a:nth-child(1)[data-acid='sort-feature.COMP.3']"
             )

      assert has_element?(
               view,
               "#test-coverage-grid > a:nth-child(1)[data-acid='sort-feature.COMP.3']"
             )

      view
      |> element("#sort-requirements-refs-count")
      |> render_click()

      assert has_element?(
               view,
               "#requirements-list-table tbody tr:nth-child(1) td:nth-child(1)",
               "sort-feature.COMP.2"
             )

      assert has_element?(
               view,
               "#requirements-coverage-grid > a:nth-child(1)[data-acid='sort-feature.COMP.2']"
             )

      assert has_element?(
               view,
               "#test-coverage-grid > a:nth-child(1)[data-acid='sort-feature.COMP.2']"
             )

      view
      |> element("#sort-requirements-refs-count")
      |> render_click()

      assert has_element?(
               view,
               "#requirements-list-table tbody tr:nth-child(1) td:nth-child(1)",
               "sort-feature.COMP.3"
             )

      assert has_element?(
               view,
               "#requirements-coverage-grid > a:nth-child(1)[data-acid='sort-feature.COMP.3']"
             )

      assert has_element?(
               view,
               "#test-coverage-grid > a:nth-child(1)[data-acid='sort-feature.COMP.3']"
             )
    end

    # feature-impl-view.LIST.4: Refs column shows total number of code references across all tracked branches
    test "Refs column shows total count of all references", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      # Add references via spec_impl_refs - both test and non-test
      create_spec_impl_ref(spec, impl,
        refs: %{
          "my-feature.COMP.1" => [
            %{
              "path" => "lib/file1.ex:1",
              "is_test" => false
            },
            %{
              "path" => "lib/file2.ex:2",
              "is_test" => false
            },
            %{
              "path" => "test/file_test.ex:10",
              "is_test" => true
            }
          ]
        }
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # feature-impl-view.LIST.4: Should show total count 3 (2 non-test + 1 test) in Refs column
      # Use stable DOM selector for the row
      assert has_element?(view, "#requirement-row-my-feature-COMP-1")
      # The row should contain the refs count in the 4th column
      assert has_element?(view, "#requirement-row-my-feature-COMP-1 td:nth-child(4)", "3")
    end

    # implementation-view.TEST_COVERAGE: Tests are still tracked for coverage grid display
    test "test coverage grid shows count of test references", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      spec = create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      # Add test references via spec_impl_refs
      create_spec_impl_ref(spec, impl,
        refs: %{
          "my-feature.COMP.1" => [
            %{
              "path" => "test/file1_test.ex:1",
              "is_test" => true
            },
            %{
              "path" => "test/file2_test.ex:2",
              "is_test" => true
            },
            %{
              "path" => "test/file3_test.ex:3",
              "is_test" => true
            }
          ]
        }
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Test coverage grid should show count 3 in the chip
      assert has_element?(view, ".bg-success", "3")
    end

    # implementation-view.REQ_LIST.5
    test "clicking row opens requirement details drawer", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Click on the table row using acid instead of requirement_id
      view
      |> element("tr[phx-value-acid='my-feature.COMP.1']")
      |> render_click()

      # Drawer should be visible
      assert has_element?(view, "#requirement-details-drawer")
    end
  end

  describe "data isolation" do
    setup :register_and_log_in_user

    test "only shows data for the correct team", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "MyImpl")
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      # Create another team with different implementation
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      other_product = create_product(other_team, "TestProduct")
      other_impl = create_implementation_for_product(other_product, name: "OtherImpl")

      create_spec_for_feature(other_team, other_product, "my-feature",
        for_implementation: other_impl
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Should show the correct implementation in dropdown button
      assert has_element?(view, "button[popovertarget='impl-popover']", "MyImpl")
      refute has_element?(view, "button[popovertarget='impl-popover']", "OtherImpl")
    end

    test "redirects when trying to access other team's implementation", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      # Create another team with implementation
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      other_product = create_product(other_team, "TestProduct")
      other_impl = create_implementation_for_product(other_product, name: "OtherImpl")

      create_spec_for_feature(other_team, other_product, "other-feature",
        for_implementation: other_impl
      )

      # Try to access other team's implementation via our team's URL
      slug = build_impl_slug(other_impl)

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert redirect_to == ~p"/t/#{team.name}/f/my-feature"
    end
  end

  describe "requirement details drawer integration" do
    setup :register_and_log_in_user

    test "drawer shows requirement details when opened", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)

      requirements = %{
        "my-feature.COMP.1" => %{
          "definition" => "My test requirement definition",
          "note" => "Test note",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      create_spec_for_feature(team, product, "my-feature",
        for_implementation: impl,
        requirements: requirements
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer using the phx-click event with acid
      view |> render_click("open_drawer", %{"acid" => "my-feature.COMP.1"})

      # Should show requirement details
      assert has_element?(view, "#requirement-details-drawer")
      assert has_element?(view, "h2", "my-feature.COMP.1")
      assert has_element?(view, "p", "My test requirement definition")
    end

    test "drawer can be closed", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> render_click("open_drawer", %{"acid" => "my-feature.COMP.1"})

      # Close drawer - use specific selector for requirement details drawer
      view
      |> element("#requirement-details-drawer button[aria-label='Close drawer']")
      |> render_click()

      # Drawer should be hidden
      refute has_element?(view, "#requirement-details-drawer .translate-x-0")
    end

    test "same requirement can be opened multiple times", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)
      # feature-impl-view.ROUTING.4: Spec must be on implementation's tracked branch
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer for first time
      view |> render_click("open_drawer", %{"acid" => "my-feature.COMP.1"})
      assert has_element?(view, "#requirement-details-drawer .translate-x-0")
      assert has_element?(view, "#requirement-details-drawer h2", "my-feature.COMP.1")

      # Close drawer - use specific selector for requirement details drawer
      view
      |> element("#requirement-details-drawer button[aria-label='Close drawer']")
      |> render_click()

      refute has_element?(view, "#requirement-details-drawer .translate-x-0")

      # Open same requirement again - should work
      view |> render_click("open_drawer", %{"acid" => "my-feature.COMP.1"})
      assert has_element?(view, "#requirement-details-drawer .translate-x-0")
      assert has_element?(view, "#requirement-details-drawer h2", "my-feature.COMP.1")
    end

    # feature-impl-view.INHERITANCE.2
    # feature-impl-view.DRAWER.3
    test "drawer shows inherited status and comment for child implementation", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create parent implementation with tracked branch and state
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      parent_tracked_branch =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      # Load the branch for the spec
      parent_branch = Acai.Repo.get!(Acai.Implementations.Branch, parent_tracked_branch.branch_id)

      spec =
        spec_fixture(product, %{
          feature_name: "inherited-feature",
          branch: parent_branch,
          requirements: %{
            "inherited-feature.COMP.1" => %{
              "definition" => "Test req",
              "is_deprecated" => false,
              "replaced_by" => []
            }
          }
        })

      # Create state on parent with a comment
      spec_impl_state_fixture(spec, parent_impl, %{
        states: %{
          "inherited-feature.COMP.1" => %{
            "status" => "completed",
            "comment" => "This is the inherited status comment"
          }
        }
      })

      # Create child implementation without its own state - will inherit from parent
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      slug = build_impl_slug(child_impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/inherited-feature")

      # Open drawer for the requirement
      view |> render_click("open_drawer", %{"acid" => "inherited-feature.COMP.1"})

      # Drawer should show the inherited status
      assert has_element?(view, "#requirement-details-drawer")
      # Should show the inherited "completed" status
      assert has_element?(view, "#requirement-details-drawer", "completed")
      # Should show the inherited status comment
      assert has_element?(
               view,
               "#requirement-details-drawer",
               "This is the inherited status comment"
             )

      # feature-impl-view.INHERITANCE.2: Drawer should show Inherited badge with unique ID
      # ACID dots are converted to dashes for DOM-safe IDs
      inherited_badge_id = "drawer-inherited-badge-inherited-feature-COMP-1"
      assert has_element?(view, "##{inherited_badge_id}", "Inherited")

      # feature-impl-view.INHERITANCE.2: Inherited badge should have popovertarget attribute
      assert has_element?(
               view,
               "button[popovertarget='drawer-inherited-popover-inherited-feature-COMP-1']"
             )

      # feature-impl-view.INHERITANCE.2: Popover container should exist with correct ID
      assert has_element?(view, "#drawer-inherited-popover-inherited-feature-COMP-1")

      # feature-impl-view.INHERITANCE.2: Popover should contain explanatory copy
      assert has_element?(
               view,
               "#drawer-inherited-popover-inherited-feature-COMP-1",
               "No states have been added for this implementation"
             )

      # feature-impl-view.INHERITANCE.2: Popover should contain source implementation link wrapper with stable ID
      assert has_element?(view, "#drawer-inherited-source-wrapper", parent_impl.name)

      # feature-impl-view.INHERITANCE.2: Source link should navigate to parent implementation
      # The link uses implementation slug format: {name}-{uuid_without_dashes}
      slug = Acai.Implementations.implementation_slug(parent_impl)

      assert has_element?(
               view,
               "a[href='/t/#{team.name}/i/#{slug}/f/inherited-feature']",
               parent_impl.name
             )
    end
  end

  describe "canonical spec resolution with inheritance" do
    setup :register_and_log_in_user

    # feature-impl-view.INHERITANCE.1
    test "finds spec on tracked branch when available", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create implementation with tracked branch
      impl = create_implementation_for_product(product, name: "ChildImpl")

      tracked_branch =
        tracked_branch_fixture(impl, repo_uri: "github.com/org/repo", branch_name: "main")

      # Load the branch for the spec
      branch = Acai.Repo.get!(Acai.Implementations.Branch, tracked_branch.branch_id)

      # Create spec on the tracked branch
      spec_fixture(product, %{
        feature_name: "inherited-feature",
        feature_description: "Local spec on tracked branch",
        path: "features/inherited-feature/feature.yaml",
        repo_uri: "github.com/org/repo",
        branch: branch,
        requirements: %{
          "inherited-feature.COMP.1" => %{
            "definition" => "Local req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/inherited-feature")

      # Should render the implementation name in dropdown button
      assert has_element?(view, "button[popovertarget='impl-popover']", "ChildImpl")
    end

    # feature-impl-view.INHERITANCE.1
    test "inherits spec from parent when not on tracked branches", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create parent implementation with tracked branch and spec
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      parent_tracked_branch =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      # Load the branch for the spec
      parent_branch = Acai.Repo.get!(Acai.Implementations.Branch, parent_tracked_branch.branch_id)

      spec_fixture(product, %{
        feature_name: "inherited-feature",
        feature_description: "Inherited from parent",
        path: "features/inherited-feature/feature.yaml",
        repo_uri: "github.com/org/repo",
        branch: parent_branch,
        requirements: %{
          "inherited-feature.COMP.1" => %{
            "definition" => "Inherited req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create child implementation without tracked branch
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      slug = build_impl_slug(child_impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/inherited-feature")

      # Should render the child implementation in dropdown button with inherited spec
      assert has_element?(view, "button[popovertarget='impl-popover']", "ChildImpl")
      # Should show requirement from inherited spec
      assert has_element?(view, "td", "inherited-feature.COMP.1")
    end

    # feature-impl-view.INHERITANCE.2
    test "inherits states from parent when not found locally", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create parent implementation with tracked branch and state
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      parent_tracked_branch =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      # Load the branch for the spec
      parent_branch = Acai.Repo.get!(Acai.Implementations.Branch, parent_tracked_branch.branch_id)

      spec =
        spec_fixture(product, %{
          feature_name: "inherited-feature",
          branch: parent_branch,
          requirements: %{
            "inherited-feature.COMP.1" => %{
              "definition" => "Test req",
              "is_deprecated" => false,
              "replaced_by" => []
            }
          }
        })

      # Create state on parent
      spec_impl_state_fixture(spec, parent_impl, %{
        states: %{
          "inherited-feature.COMP.1" => %{"status" => "completed", "comment" => "Done in parent"}
        }
      })

      # Create child implementation without state
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      slug = build_impl_slug(child_impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/inherited-feature")

      # Should show the inherited completed status with lighter color (30% opacity)
      assert has_element?(view, ".bg-info\\/30[title='inherited-feature.COMP.1']")
    end

    # feature-impl-view.INHERITANCE.3
    # feature-impl-view.LIST.4: Refs column shows total number of code references across all tracked branches
    test "inherits refs from parent's tracked branches", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create parent implementation with tracked branch and refs
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      parent_tracked_branch =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      # Load the branch for the spec
      parent_branch = Acai.Repo.get!(Acai.Implementations.Branch, parent_tracked_branch.branch_id)

      spec =
        spec_fixture(product, %{
          feature_name: "inherited-feature",
          branch: parent_branch,
          requirements: %{
            "inherited-feature.COMP.1" => %{
              "definition" => "Test req",
              "is_deprecated" => false,
              "replaced_by" => []
            }
          }
        })

      # Create refs on parent - one test and one non-test
      create_spec_impl_ref(spec, parent_impl,
        refs: %{
          "inherited-feature.COMP.1" => [
            %{"path" => "lib/file.ex:10", "is_test" => false},
            %{"path" => "test/file_test.ex:10", "is_test" => true}
          ]
        }
      )

      # Create child implementation without tracked branches
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      slug = build_impl_slug(child_impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/inherited-feature")

      # feature-impl-view.LIST.4: Refs column shows TOTAL count (test + non-test = 2)
      # Use stable DOM selector for the row
      assert has_element?(view, "#requirement-row-inherited-feature-COMP-1")
      # The row should contain the refs count in the 4th column
      assert has_element?(view, "#requirement-row-inherited-feature-COMP-1 td:nth-child(4)", "2")
    end

    test "redirects when no spec exists in ancestry", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create implementation without any spec on its branches or parent
      impl = create_implementation_for_product(product, name: "OrphanImpl")
      # Don't create any spec or tracked branch

      slug = build_impl_slug(impl)

      # Should redirect because no spec exists
      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/t/#{team.name}/i/#{slug}/f/nonexistent-feature")

      assert redirect_to == ~p"/t/#{team.name}/f/nonexistent-feature"
    end
  end

  describe "SELECTOR_SCOPE - dropdown option scoping" do
    setup :register_and_log_in_user

    # feature-impl-view.CARDS.1-3
    test "feature dropdown excludes features from another product on shared tracked branch", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)

      # Create two products in the same team
      product_a = create_product(team, "ProductA")
      product_b = create_product(team, "ProductB")

      # Create implementations for each product
      impl_a = create_implementation_for_product(product_a, name: "ImplA")
      impl_b = create_implementation_for_product(product_b, name: "ImplB")

      # Create a shared branch that both implementations track
      shared_branch =
        branch_fixture(team, %{repo_uri: "github.com/org/shared", branch_name: "main"})

      # Both implementations track the same branch
      tracked_branch_fixture(impl_a, branch: shared_branch, repo_uri: shared_branch.repo_uri)
      tracked_branch_fixture(impl_b, branch: shared_branch, repo_uri: shared_branch.repo_uri)

      # Create specs on the shared branch for each product (different features)
      spec_fixture(product_a, %{
        feature_name: "product-a-feature",
        branch: shared_branch,
        requirements: %{
          "product-a-feature.COMP.1" => %{
            "definition" => "A req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      spec_fixture(product_b, %{
        feature_name: "product-b-feature",
        branch: shared_branch,
        requirements: %{
          "product-b-feature.COMP.1" => %{
            "definition" => "B req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # When viewing impl_a, should only see product-a-feature
      slug_a = build_impl_slug(impl_a)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug_a}/f/product-a-feature")

      # Feature dropdown should contain product-a-feature
      assert has_element?(view, "#feature-popover", "product-a-feature")
      # Feature dropdown should NOT contain product-b-feature (different product)
      refute has_element?(view, "#feature-popover", "product-b-feature")
    end

    # feature-impl-view.CARDS.1-3
    test "feature dropdown includes inherited features for the selected implementation", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      parent_tracked_branch =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.get!(Acai.Implementations.Branch, parent_tracked_branch.branch_id)

      spec_fixture(product, %{
        feature_name: "inherited-feature",
        branch: parent_branch,
        requirements: %{
          "inherited-feature.COMP.1" => %{
            "definition" => "Inherited req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      slug = build_impl_slug(child_impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/inherited-feature")

      assert has_element?(view, "#feature-popover", "inherited-feature")
    end

    # feature-impl-view.ROUTING.4: URL should not resolve feature from another product
    test "does not resolve feature from another product on shared tracked branch", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)

      # Create two products in the same team
      product_a = create_product(team, "ProductA")
      product_b = create_product(team, "ProductB")

      # Create implementations for each product
      impl_a = create_implementation_for_product(product_a, name: "ImplA")
      impl_b = create_implementation_for_product(product_b, name: "ImplB")

      # Create a shared branch that both implementations track
      shared_branch =
        branch_fixture(team, %{repo_uri: "github.com/org/shared", branch_name: "main"})

      # Both implementations track the same branch
      tracked_branch_fixture(impl_a, branch: shared_branch, repo_uri: shared_branch.repo_uri)
      tracked_branch_fixture(impl_b, branch: shared_branch, repo_uri: shared_branch.repo_uri)

      # Create a spec ONLY for product_a on the shared branch
      spec_fixture(product_a, %{
        feature_name: "product-a-only-feature",
        branch: shared_branch,
        requirements: %{
          "product-a-only-feature.COMP.1" => %{
            "definition" => "Product A only req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # impl_a should successfully render the feature (same product as spec)
      slug_a = build_impl_slug(impl_a)
      {:ok, view_a, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug_a}/f/product-a-only-feature")

      # Should show the implementation name
      assert has_element?(view_a, "button[popovertarget='impl-popover']", "ImplA")
      # Should show the feature requirements
      assert has_element?(view_a, "td", "Product A only req")

      # impl_b should redirect because the spec belongs to a different product
      slug_b = build_impl_slug(impl_b)

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/t/#{team.name}/i/#{slug_b}/f/product-a-only-feature")

      # Should redirect to feature view
      assert redirect_to == ~p"/t/#{team.name}/f/product-a-only-feature"
    end

    # feature-impl-view.CARDS.1-4
    test "implementation dropdown excludes sibling without the current feature", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create three implementations:
      # - impl_with_feature: tracks a branch with the feature
      # - impl_without_feature: tracks a different branch WITHOUT the feature
      # - impl_inherited: child of impl_with_feature, inherits the feature
      impl_with_feature = create_implementation_for_product(product, name: "WithFeature")
      impl_without_feature = create_implementation_for_product(product, name: "WithoutFeature")

      # Create tracked branches and specs
      branch_with_spec =
        branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})

      branch_without_spec =
        branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})

      tracked_branch_fixture(impl_with_feature,
        branch: branch_with_spec,
        repo_uri: branch_with_spec.repo_uri
      )

      tracked_branch_fixture(impl_without_feature,
        branch: branch_without_spec,
        repo_uri: branch_without_spec.repo_uri
      )

      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: branch_with_spec,
        requirements: %{
          "test-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # impl_with_feature should only show itself in dropdown (not impl_without_feature)
      slug = build_impl_slug(impl_with_feature)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/test-feature")

      # Implementation dropdown should contain impl_with_feature
      assert has_element?(view, "#impl-popover", "WithFeature")
      # Implementation dropdown should NOT contain impl_without_feature (can't resolve feature)
      refute has_element?(view, "#impl-popover", "WithoutFeature")
    end

    # feature-impl-view.CARDS.1-4
    test "implementation dropdown includes implementation that inherits feature from parent", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create parent implementation with tracked branch and spec
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      parent_tracked_branch =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.get!(Acai.Implementations.Branch, parent_tracked_branch.branch_id)

      spec_fixture(product, %{
        feature_name: "inherited-feature",
        branch: parent_branch,
        requirements: %{
          "inherited-feature.COMP.1" => %{
            "definition" => "Inherited req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create child implementation without tracked branches - will inherit spec from parent
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      # When viewing the child implementation, both parent and child should be in dropdown
      slug_child = build_impl_slug(child_impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug_child}/f/inherited-feature")

      # Implementation dropdown should contain child_impl (inherits the feature)
      assert has_element?(view, "#impl-popover", "ChildImpl")
      # Implementation dropdown should also contain parent_impl (has feature directly)
      assert has_element?(view, "#impl-popover", "ParentImpl")
    end
  end

  describe "CARDS - interactive header and cards" do
    setup :register_and_log_in_user

    # feature-impl-view.CARDS.1
    test "renders interactive title header with implementation and feature dropdowns", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Check that implementation dropdown button exists
      assert has_element?(view, "button[popovertarget='impl-popover']", "Production")
      # Check that feature dropdown button exists
      assert has_element?(view, "button[popovertarget='feature-popover']", "my-feature")
    end

    # feature-impl-view.CARDS.1-1
    test "implementation dropdown shows available implementations for the product", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl1 = create_implementation_for_product(product, name: "Production")
      impl2 = create_implementation_for_product(product, name: "Staging")

      # Create spec for first implementation
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl1)
      # Also create spec for second implementation
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl2)

      slug = build_impl_slug(impl1)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Both implementations should be available in dropdown menu
      assert has_element?(view, "#impl-popover", "Production")
      assert has_element?(view, "#impl-popover", "Staging")
    end

    # feature-impl-view.CARDS.1-2
    test "changing implementation dropdown patches the URL and updates view state", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl1 = create_implementation_for_product(product, name: "Production")
      impl2 = create_implementation_for_product(product, name: "Staging")

      # Create specs for both implementations with different requirements
      create_spec_for_feature(team, product, "my-feature",
        for_implementation: impl1,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Production req 1",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      )

      create_spec_for_feature(team, product, "my-feature",
        for_implementation: impl2,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Staging req 1",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      )

      slug1 = build_impl_slug(impl1)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug1}/f/my-feature")

      # Verify initial state shows Production
      assert has_element?(view, "button[popovertarget='impl-popover']", "Production")
      assert has_element?(view, "td", "Production req 1")

      # Change implementation dropdown
      slug2 = build_impl_slug(impl2)

      view
      |> element("#impl-popover a", "Staging")
      |> render_click(%{impl_id: slug2})

      # Verify patch navigation occurred with correct URL
      assert_patch(view, ~p"/t/#{team.name}/i/#{slug2}/f/my-feature")

      # Verify view state was updated: Staging is now selected
      assert has_element?(view, "button[popovertarget='impl-popover']", "Staging")

      # Verify requirements were reloaded for the new implementation
      assert has_element?(view, "td", "Staging req 1")
      refute has_element?(view, "td", "Production req 1")

      # Verify tracked branches were updated (Staging implementation should show its branches)
      assert has_element?(view, ".card", "Tracked Branches")
    end

    # feature-impl-view.CARDS.1-2
    test "changing feature dropdown patches the URL and updates view state", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create a branch for the spec
      branch = branch_fixture(team)
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create specs for multiple features on the same branch with different requirements
      spec_fixture(product, %{
        feature_name: "feature-a",
        branch: branch,
        path: "features/feature-a/spec.yaml",
        requirements: %{
          "feature-a.COMP.1" => %{
            "definition" => "Feature A requirement",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      spec_fixture(product, %{
        feature_name: "feature-b",
        branch: branch,
        path: "features/feature-b/spec.yaml",
        requirements: %{
          "feature-b.COMP.1" => %{
            "definition" => "Feature B requirement",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/feature-a")

      # Verify initial state shows feature-a
      assert has_element?(view, "button[popovertarget='feature-popover']", "feature-a")
      assert has_element?(view, "td", "Feature A requirement")
      assert has_element?(view, ".card", "features/feature-a/spec.yaml")

      # Change feature dropdown
      view
      |> element("#feature-popover a", "feature-b")
      |> render_click(%{feature_name: "feature-b"})

      # Verify patch navigation occurred with correct URL
      assert_patch(view, ~p"/t/#{team.name}/i/#{slug}/f/feature-b")

      # Verify view state was updated: feature-b is now selected
      assert has_element?(view, "button[popovertarget='feature-popover']", "feature-b")

      # Verify requirements were reloaded for the new feature
      assert has_element?(view, "td", "Feature B requirement")
      refute has_element?(view, "td", "Feature A requirement")

      # Verify target spec card shows new feature's spec path
      assert has_element?(view, ".card", "features/feature-b/spec.yaml")
      refute has_element?(view, ".card", "features/feature-a/spec.yaml")
    end

    # feature-impl-view.CARDS.2
    test "renders target spec card with labeled fields", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch first
      branch = branch_fixture(team, %{repo_uri: "github.com/org/test-repo", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on the tracked branch
      spec_fixture(product, %{
        feature_name: "my-feature",
        path: "features/my-feature/spec.yaml",
        branch: branch,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Check for labeled fields
      assert has_element?(view, ".card", "Target Spec")
      assert has_element?(view, ".card", "Repo")
      # Now shows only repo name for known patterns (GitHub)
      assert has_element?(view, ".card", "test-repo")
      assert has_element?(view, ".card", "Branch")
      assert has_element?(view, ".card", "main")
      assert has_element?(view, ".card", "Path")
      assert has_element?(view, ".card", "features/my-feature/spec.yaml")
    end

    # feature-impl-view.CARDS.2-2: No badge shown when spec is on tracked branch (local)
    test "target spec card shows no badge when spec is on tracked branch", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Should not show any badge when spec is local (not inherited)
      refute has_element?(view, ".badge", "Inherited")
    end

    # feature-impl-view.CARDS.2-2: Inherited badge
    test "target spec card shows Inherited badge when spec is from parent", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create parent implementation with tracked branch and spec
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      parent_tracked_branch =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.get!(Acai.Implementations.Branch, parent_tracked_branch.branch_id)

      spec_fixture(product, %{
        feature_name: "inherited-feature",
        branch: parent_branch,
        requirements: %{
          "inherited-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create child implementation without tracked branch
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      slug = build_impl_slug(child_impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/inherited-feature")

      # Should show Inherited badge
      assert has_element?(view, ".badge", "Inherited")
      refute has_element?(view, ".badge", "Pushed")
    end

    # feature-impl-view.CARDS.3
    test "renders tracked branches card with branch names", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create multiple tracked branches with different repo_uris
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})

      tracked_branch_fixture(impl, branch: branch1, repo_uri: branch1.repo_uri)
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      # Create spec on first branch
      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch1,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Check that tracked branches card shows branch names
      assert has_element?(view, ".card", "Tracked Branches")
      assert has_element?(view, ".card", "main")
      assert has_element?(view, ".card", "develop")
    end

    # feature-impl-view.CARDS.3
    test "tracked branches card shows empty state when no branches", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create parent implementation with tracked branch and spec
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      parent_tracked_branch =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.get!(Acai.Implementations.Branch, parent_tracked_branch.branch_id)

      spec_fixture(product, %{
        feature_name: "inherited-feature",
        branch: parent_branch,
        requirements: %{
          "inherited-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create child implementation without tracked branches - will inherit spec
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      slug = build_impl_slug(child_impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/inherited-feature")

      # Should show empty state
      assert has_element?(view, ".card", "Tracked Branches")
      assert has_element?(view, ".card", "No tracked branches")
    end

    # feature-impl-view.CARDS.4
    test "renders feature description from target spec", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch first
      branch = branch_fixture(team, %{repo_uri: "github.com/org/test-repo", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec with a specific feature description
      spec_fixture(product, %{
        feature_name: "my-feature",
        feature_description: "This is the amazing feature description for testing",
        path: "features/my-feature/spec.yaml",
        branch: branch,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # feature-impl-view.CARDS.4: Description should be visible in target spec card
      assert has_element?(
               view,
               "#feature-description",
               "This is the amazing feature description for testing"
             )
    end

    # feature-impl-view.CARDS.4
    # feature-impl-view.INHERITANCE.1
    test "renders inherited feature description from ancestor spec", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create parent implementation with tracked branch and spec with description
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      parent_tracked_branch =
        tracked_branch_fixture(parent_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.get!(Acai.Implementations.Branch, parent_tracked_branch.branch_id)

      spec_fixture(product, %{
        feature_name: "inherited-feature",
        feature_description: "This is the inherited feature description from parent",
        path: "features/inherited-feature/spec.yaml",
        branch: parent_branch,
        requirements: %{
          "inherited-feature.COMP.1" => %{
            "definition" => "Inherited req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create child implementation without tracked branch - will inherit spec from parent
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      slug = build_impl_slug(child_impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/inherited-feature")

      # feature-impl-view.CARDS.4: Inherited description should be visible
      # feature-impl-view.INHERITANCE.1: Description comes from ancestor-resolved spec
      assert has_element?(
               view,
               "#feature-description",
               "This is the inherited feature description from parent"
             )
    end

    # feature-impl-view.CARDS.4
    test "handles nil feature description gracefully", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch first
      branch = branch_fixture(team, %{repo_uri: "github.com/org/test-repo", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec without feature_description (nil)
      spec_fixture(product, %{
        feature_name: "my-feature",
        feature_description: nil,
        path: "features/my-feature/spec.yaml",
        branch: branch,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # feature-impl-view.CARDS.4: Page should be stable when description is nil
      # Description section should not be rendered when nil
      refute has_element?(view, "#feature-description")
      # But the rest of the page should still render
      assert has_element?(view, ".card", "Target Spec")
    end
  end

  describe "REPO_DISPLAY - repository name display formatting" do
    setup :register_and_log_in_user

    # feature-impl-view.CARDS.2-2
    # feature-impl-view.CARDS.2-3
    test "target spec card shows only repo name for GitHub URIs", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch with GitHub URI
      branch = branch_fixture(team, %{repo_uri: "github.com/owner/my-repo", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        path: "features/my-feature/spec.yaml",
        branch: branch,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # feature-impl-view.CARDS.2-2: The visible badge shows only the repo name
      assert has_element?(
               view,
               "button[popovertarget='target-spec-repo-popover-#{branch.id}']",
               "my-repo"
             )

      # The full URI moves into the popover link
      assert has_element?(
               view,
               "#target-spec-repo-popover-#{branch.id} a[href='https://github.com/owner/my-repo']"
             )
    end

    # feature-impl-view.CARDS.2-2
    # feature-impl-view.CARDS.2-3
    test "target spec card shows only repo name for GitLab URIs", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch with GitLab URI
      branch = branch_fixture(team, %{repo_uri: "gitlab.com/group/project", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        path: "features/my-feature/spec.yaml",
        branch: branch,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # feature-impl-view.CARDS.2-2: The visible badge shows only the repo name
      assert has_element?(
               view,
               "button[popovertarget='target-spec-repo-popover-#{branch.id}']",
               "project"
             )

      # The full URI moves into the popover link
      assert has_element?(
               view,
               "#target-spec-repo-popover-#{branch.id} a[href='https://gitlab.com/group/project']"
             )
    end

    # feature-impl-view.CARDS.2-4
    test "target spec card shows full repo_uri for unknown patterns", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch with unknown URI pattern
      unknown_uri = "bitbucket.org/team/project"
      branch = branch_fixture(team, %{repo_uri: unknown_uri, branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        path: "features/my-feature/spec.yaml",
        branch: branch,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # feature-impl-view.CARDS.2-4: Should show the full URI for unknown patterns
      assert has_element?(view, ".card", "bitbucket.org/team/project")
    end

    # feature-impl-view.CARDS.3-1
    test "tracked branches card uses repo name display for GitHub URIs", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create spec on a tracked branch first
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/spec-repo", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch1, repo_uri: branch1.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch1,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create another tracked branch with different GitHub repo
      branch2 =
        branch_fixture(team, %{repo_uri: "github.com/org/another-repo", branch_name: "develop"})

      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # feature-impl-view.CARDS.3-1: Tracked branches card should use same display rules
      # Visible badges show only repo names and popovers carry the full URI links
      assert has_element?(
               view,
               "button[popovertarget='tracked-branch-repo-popover-#{branch1.id}']",
               "spec-repo"
             )

      assert has_element?(
               view,
               "button[popovertarget='tracked-branch-repo-popover-#{branch2.id}']",
               "another-repo"
             )

      assert has_element?(
               view,
               "#tracked-branch-repo-popover-#{branch1.id} a[href='https://github.com/org/spec-repo']"
             )

      assert has_element?(
               view,
               "#tracked-branch-repo-popover-#{branch2.id} a[href='https://github.com/org/another-repo']"
             )
    end

    # feature-impl-view.CARDS.3-1
    test "tracked branches card preserves full URI for unknown patterns", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create spec on a tracked branch with known pattern
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/spec-repo", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch1, repo_uri: branch1.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch1,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create another tracked branch with unknown pattern
      unknown_uri = "custom-git.example.com/team/project"
      branch2 = branch_fixture(team, %{repo_uri: unknown_uri, branch_name: "develop"})
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # feature-impl-view.CARDS.3-1: Known pattern shows repo name
      assert has_element?(view, ".card", "spec-repo")
      # feature-impl-view.CARDS.3-1: Unknown pattern shows full URI
      assert has_element?(view, ".card", "custom-git.example.com/team/project")
    end

    # feature-impl-view.CARDS.2-4
    # Regression test: hosts that share a prefix with known hosts should NOT be reformatted
    test "target spec card shows full URI for hosts sharing prefix with known hosts", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch with URI that shares prefix with github.com but is different
      # github.com.au should NOT be treated as github.com
      unknown_uri = "github.com.au/team/unique-project-name-12345"
      branch = branch_fixture(team, %{repo_uri: unknown_uri, branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        path: "features/my-feature/spec.yaml",
        branch: branch,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # feature-impl-view.CARDS.2-4: Should show the full URI
      assert has_element?(view, ".card", "github.com.au/team/unique-project-name-12345")
    end

    # feature-impl-view.CARDS.3-1
    # Regression test: tracked branches with prefix-sharing hosts
    test "tracked branches card shows full URI for hosts sharing prefix with known hosts", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create spec on a tracked branch with known pattern
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/spec-repo", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch1, repo_uri: branch1.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch1,
        requirements: %{
          "my-feature.COMP.1" => %{
            "definition" => "Test req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create tracked branch with gitlab.com.internal (shares prefix with gitlab.com)
      # Using a unique project name to avoid conflicts with other page content
      prefix_uri = "gitlab.com.internal/group/unique-internal-project-98765"
      branch2 = branch_fixture(team, %{repo_uri: prefix_uri, branch_name: "develop"})
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Known pattern shows repo name
      assert has_element?(view, ".card", "spec-repo")
      # Prefix-sharing host should show full URI
      assert has_element?(
               view,
               ".card",
               "gitlab.com.internal/group/unique-internal-project-98765"
             )
    end
  end

  describe "PATCH_NAVIGATION - dropdown patch navigation and handle_params" do
    setup :register_and_log_in_user

    # feature-impl-view.CARDS.1-2
    test "select_feature patches URL without full page reload", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      impl = create_implementation_for_product(product, name: "TestImpl")

      # Create tracked branch for the implementation
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create two specs for different features on the same branch
      spec_fixture(product, %{
        feature_name: "feature-one",
        branch: branch,
        requirements: %{
          "feature-one.COMP.1" => %{
            "definition" => "Feature one req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      spec_fixture(product, %{
        feature_name: "feature-two",
        branch: branch,
        requirements: %{
          "feature-two.COMP.1" => %{
            "definition" => "Feature two req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/feature-one")

      # Click on feature dropdown option to select different feature
      view
      |> element("a[phx-click='select_feature'][phx-value-feature_name='feature-two']")
      |> render_click()

      # Should patch to the new URL (check current path updated)
      assert render(view) =~ "feature-two"
      # Implementation name should still be visible
      assert has_element?(view, "button[popovertarget='impl-popover']", "TestImpl")
    end

    # feature-impl-view.CARDS.1-2
    test "select_implementation patches URL without full page reload", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create two implementations that share the same feature via tracked branches
      impl_a = create_implementation_for_product(product, name: "ImplA")
      impl_b = create_implementation_for_product(product, name: "ImplB")

      # Create a shared branch with the feature spec
      shared_branch =
        branch_fixture(team, %{repo_uri: "github.com/org/shared", branch_name: "main"})

      # Both implementations track the same branch
      tracked_branch_fixture(impl_a, branch: shared_branch, repo_uri: shared_branch.repo_uri)
      tracked_branch_fixture(impl_b, branch: shared_branch, repo_uri: shared_branch.repo_uri)

      # Create spec on the shared branch
      spec_fixture(product, %{
        feature_name: "shared-feature",
        branch: shared_branch,
        requirements: %{
          "shared-feature.COMP.1" => %{
            "definition" => "Shared req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug_a = build_impl_slug(impl_a)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug_a}/f/shared-feature")

      # Verify starting state
      assert has_element?(view, "button[popovertarget='impl-popover']", "ImplA")

      # Get slug for impl_b
      slug_b = build_impl_slug(impl_b)

      # Click on implementation dropdown option
      view
      |> element("a[phx-click='select_implementation'][phx-value-impl_id='#{slug_b}']")
      |> render_click()

      # Should patch to the new implementation
      assert render(view) =~ "ImplB"
    end

    # feature-impl-view.CARDS.1-4
    test "select_implementation rejects invalid implementation via event handler", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      impl_a = create_implementation_for_product(product, name: "ImplA")
      impl_b = create_implementation_for_product(product, name: "ImplB")

      # Create branch and spec only for impl_a
      branch_a = branch_fixture(team, %{repo_uri: "github.com/org/repo-a", branch_name: "main"})
      tracked_branch_fixture(impl_a, branch: branch_a, repo_uri: branch_a.repo_uri)

      spec_fixture(product, %{
        feature_name: "exclusive-feature",
        branch: branch_a,
        requirements: %{
          "exclusive-feature.COMP.1" => %{
            "definition" => "Exclusive req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # impl_b tracks a different branch without the spec
      branch_b = branch_fixture(team, %{repo_uri: "github.com/org/repo-b", branch_name: "main"})
      tracked_branch_fixture(impl_b, branch: branch_b, repo_uri: branch_b.repo_uri)

      slug_a = build_impl_slug(impl_a)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug_a}/f/exclusive-feature")

      # Try to select impl_b which doesn't have this feature
      # Use direct event call since the dropdown won't show invalid implementations
      slug_b = build_impl_slug(impl_b)

      # Send the event directly as if the user manipulated the DOM
      result = view |> render_click("select_implementation", %{"impl_id" => slug_b})

      # Should show error flash
      assert result =~ "Implementation is not available for this feature"
    end

    # feature-impl-view.CARDS.1-2
    test "handle_params reuses existing assigns when only feature changes", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      impl = create_implementation_for_product(product, name: "TestImpl")

      # Create tracked branch for the implementation
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create two specs for different features on the same branch
      spec_fixture(product, %{
        feature_name: "feature-one",
        branch: branch,
        requirements: %{
          "feature-one.COMP.1" => %{
            "definition" => "Feature one req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      spec_fixture(product, %{
        feature_name: "feature-two",
        branch: branch,
        requirements: %{
          "feature-two.COMP.1" => %{
            "definition" => "Feature two req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/feature-one")

      # Switch to feature-two via patch
      view
      |> element("a[phx-click='select_feature'][phx-value-feature_name='feature-two']")
      |> render_click()

      # Should show feature-two content
      assert render(view) =~ "feature-two"
      # Implementation should still be present
      assert has_element?(view, "button[popovertarget='impl-popover']", "TestImpl")
    end
  end

  describe "IMPL_SETTINGS - implementation settings drawer" do
    setup :register_and_log_in_user

    # feature-impl-view.MAIN.2
    test "renders implementation settings button", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, "#impl-settings-btn")
    end

    # impl-settings.DRAWER.1
    # impl-settings.DRAWER.2
    # feature-impl-view.MAIN.2-1
    test "clicking settings button opens the drawer", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # impl-settings.DRAWER.1: Renders a settings icon button that opens the drawer
      view
      |> element("#impl-settings-btn")
      |> render_click()

      # Drawer should be visible (check for implementation name in drawer)
      assert has_element?(view, "#implementation-settings-drawer", "Production")
      # impl-settings.DRAWER.4: Drawer displays the implementation name and product context
      assert has_element?(view, "#implementation-settings-drawer", "TestProduct")
    end

    # impl-settings.DRAWER.3
    test "drawer closes when clicking close button", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()
      assert has_element?(view, "#implementation-settings-drawer", "Production")

      # Close drawer via close button
      view
      |> element("#implementation-settings-drawer button[aria-label='Close drawer']")
      |> render_click()

      # Drawer should be hidden (no longer shows translate-x-0)
      refute has_element?(view, "#implementation-settings-drawer-panel.translate-x-0")
    end

    # impl-settings.RENAME.1
    # impl-settings.RENAME.4
    test "rename form has pre-populated name and disabled save when unchanged", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # impl-settings.RENAME.1: Renders a text input pre-populated with the current implementation name
      assert has_element?(view, "#rename-implementation-form input[value='Production']")

      # impl-settings.RENAME.4: Save button is disabled when input value matches current name
      assert has_element?(view, "#save-rename-btn[disabled]")
    end

    # impl-settings.RENAME.5
    test "rename save is disabled when input is empty", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Clear the input
      view
      |> element("#rename-implementation-form")
      |> render_change(%{implementation: %{name: ""}})

      # impl-settings.RENAME.5: Save button is disabled when input is empty or whitespace-only
      assert has_element?(view, "#save-rename-btn[disabled]")
    end

    # impl-settings.RENAME.6
    # impl-settings.RENAME.7_1
    test "rename shows error when name already exists in product", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      # Create another implementation with name "Staging"
      _other_impl = create_implementation_for_product(product, name: "Staging")

      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Try to rename to existing name
      view
      |> element("#rename-implementation-form")
      |> render_change(%{implementation: %{name: "Staging"}})

      view
      |> element("#rename-implementation-form")
      |> render_submit(%{implementation: %{name: "Staging"}})

      # impl-settings.RENAME.7_1: On validation failure, displays error message
      assert has_element?(
               view,
               "#implementation-settings-drawer",
               "Implementation name already exists"
             )
    end

    # impl-settings.RENAME.2
    test "rename section has Save button next to input", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # impl-settings.RENAME.2: Renders a Save button next to the input
      assert has_element?(view, "#save-rename-btn", "Save")
    end

    # impl-settings.RENAME.3
    test "rename input supports editing the implementation name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "OldName")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # impl-settings.RENAME.3: Input supports editing the implementation name
      # Change the name
      view
      |> element("#rename-implementation-form")
      |> render_change(%{implementation: %{name: "NewName"}})

      # Verify input value was updated
      assert has_element?(view, "#rename-implementation-form input[value='NewName']")
    end

    # impl-settings.RENAME.7_2
    test "rename error clears when user modifies input", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      # Create another implementation with name "Staging"
      _other_impl = create_implementation_for_product(product, name: "Staging")

      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Try to rename to existing name to trigger error
      view
      |> element("#rename-implementation-form")
      |> render_change(%{implementation: %{name: "Staging"}})

      view
      |> element("#rename-implementation-form")
      |> render_submit(%{implementation: %{name: "Staging"}})

      # Verify error appears
      assert has_element?(
               view,
               "#implementation-settings-drawer",
               "Implementation name already exists"
             )

      # impl-settings.RENAME.7_2: Error clears when user modifies the input
      view
      |> element("#rename-implementation-form")
      |> render_change(%{implementation: %{name: "StagingModified"}})

      # Error should be gone
      refute has_element?(
               view,
               "#implementation-settings-drawer",
               "Implementation name already exists"
             )
    end

    # impl-settings.RENAME.8
    test "successful rename updates UI and patches URL", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "OldName")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Change name
      view
      |> element("#rename-implementation-form")
      |> render_change(%{implementation: %{name: "NewName"}})

      # Submit rename
      view
      |> element("#rename-implementation-form")
      |> render_submit(%{implementation: %{name: "NewName"}})

      # impl-settings.RENAME.8: On successful save, updates the implementation name and UI reflects change
      assert has_element?(view, "#implementation-settings-drawer", "NewName")
      # URL should be patched to new slug
      assert_patch(
        view,
        ~p"/t/#{team.name}/i/newname-#{String.replace(impl.id, "-", "")}/f/my-feature"
      )
    end

    # impl-settings.UNTRACK_BRANCH.1
    # impl-settings.UNTRACK_BRANCH.2
    test "tracked branches are listed with repo_uri and branch name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branches
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})

      tracked_branch_fixture(impl, branch: branch1, repo_uri: branch1.repo_uri)
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      # Create spec on first branch
      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch1,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # impl-settings.UNTRACK_BRANCH.1: Renders a list of all currently tracked branches
      # impl-settings.UNTRACK_BRANCH.2: Each branch entry displays the full repo_uri and branch name
      assert has_element?(view, "#implementation-settings-drawer", "github.com/org/repo1")
      assert has_element?(view, "#implementation-settings-drawer", "github.com/org/repo2")
      assert has_element?(view, "#implementation-settings-drawer", "main")
      assert has_element?(view, "#implementation-settings-drawer", "develop")
    end

    # impl-settings.UNTRACK_BRANCH.3
    test "each tracked branch has a delete icon button for removal", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branches
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})

      tracked_branch_fixture(impl, branch: branch1, repo_uri: branch1.repo_uri)
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      # Create spec on different branch so these can be untracked
      branch3 = branch_fixture(team, %{repo_uri: "github.com/org/repo3", branch_name: "feature"})
      tracked_branch_fixture(impl, branch: branch3, repo_uri: branch3.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch3,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # impl-settings.UNTRACK_BRANCH.3: Each branch has a delete icon button for removal
      # Each tracked branch should have an untrack button with trash icon
      assert has_element?(view, "#untrack-branch-btn-#{branch1.id}")
      assert has_element?(view, "#untrack-branch-btn-#{branch2.id}")
      # The buttons should use a trash icon (rendered as span with hero-trash class)
      assert has_element?(view, "#untrack-branch-btn-#{branch1.id} span.hero-trash")
      assert has_element?(view, "#untrack-branch-btn-#{branch2.id} span.hero-trash")
    end

    # impl-settings.UNTRACK_BRANCH.4_1
    test "delete button is disabled for current spec branch", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create branch for spec (this will be the current spec branch)
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      # Create another tracked branch
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # impl-settings.UNTRACK_BRANCH.4_1: Delete button is disabled for the branch containing the target spec
      assert has_element?(view, "#untrack-branch-btn-#{branch.id}[disabled]")
      # Other branch should not be disabled
      refute has_element?(view, "#untrack-branch-btn-#{branch2.id}[disabled]")
    end

    # impl-settings.UNTRACK_BRANCH.5
    # impl-settings.UNTRACK_BRANCH.6_1
    test "untrack modal shows branch name and repo_uri", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on different branch so this one can be untracked
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch2,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click untrack button
      view
      |> element("#untrack-branch-btn-#{branch.id}")
      |> render_click()

      # impl-settings.UNTRACK_BRANCH.5: Clicking a delete button opens a confirmation modal
      # impl-settings.UNTRACK_BRANCH.6_1: Confirmation modal displays the branch name and repo_uri
      assert has_element?(view, "#implementation-settings-drawer", "github.com/org/repo1")
      assert has_element?(view, "#implementation-settings-drawer", "main")
    end

    # impl-settings.UNTRACK_BRANCH.7
    test "confirming untrack removes the branch", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on different branch
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch2,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Verify branch is listed
      assert has_element?(view, "#implementation-settings-drawer", "github.com/org/repo1")

      # Click untrack button
      view
      |> element("#untrack-branch-btn-#{branch.id}")
      |> render_click()

      # Confirm untrack
      view
      |> element("#confirm-untrack-btn")
      |> render_click()

      # impl-settings.UNTRACK_BRANCH.7: On confirmation, removes the branch from tracked branches
      # impl-settings.UNTRACK_BRANCH.8: UI updates immediately to reflect the removed branch
      refute has_element?(view, "#implementation-settings-drawer", "github.com/org/repo1")
    end

    # impl-settings.TRACK_BRANCH.1
    test "show track branch UI button is visible", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Track branch button should be visible
      assert has_element?(view, "#show-track-branch-btn", "Track Branch")
    end

    # impl-settings.DELETE.1
    # impl-settings.DELETE.2
    test "delete implementation button is visible with warning styling", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # impl-settings.DELETE.1: Renders a Delete Implementation button
      # impl-settings.DELETE.2: Button is visually distinct to indicate destructive action
      assert has_element?(view, "#delete-implementation-btn")
    end

    # impl-settings.DELETE.3
    # impl-settings.DELETE.4_1
    test "delete modal shows implementation and product names", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click delete button
      view
      |> element("#delete-implementation-btn")
      |> render_click()

      # impl-settings.DELETE.3: Clicking the button opens a confirmation modal
      # impl-settings.DELETE.4_1: Modal displays the implementation name and product name
      assert has_element?(view, "#implementation-settings-drawer", "Production")
      assert has_element?(view, "#implementation-settings-drawer", "TestProduct")
      # impl-settings.DELETE.4_2: Modal displays warning text that deletion is irreversible
      assert has_element?(
               view,
               "#implementation-settings-drawer",
               "This action is permanent and cannot be undone"
             )
    end

    # impl-settings.DELETE.5
    test "delete button disabled until confirmation name is typed", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click delete button
      view
      |> element("#delete-implementation-btn")
      |> render_click()

      # impl-settings.DELETE.5: Delete button in modal requires additional confirmation (e.g. type name)
      assert has_element?(view, "#confirm-delete-btn[disabled]")

      # Type wrong name via the form
      view
      |> element("#delete-confirm-form")
      |> render_change(%{confirm_name: "WrongName"})

      # Should still be disabled
      assert has_element?(view, "#confirm-delete-btn[disabled]")

      # Type correct name via the form
      view
      |> element("#delete-confirm-form")
      |> render_change(%{confirm_name: "Production"})

      # Should now be enabled
      refute has_element?(view, "#confirm-delete-btn[disabled]")
    end

    # impl-settings.DELETE.6
    # impl-settings.DELETE.7
    test "confirming delete redirects to product page", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click delete button
      view
      |> element("#delete-implementation-btn")
      |> render_click()

      # Type confirmation
      view
      |> element("#delete-confirm-form")
      |> render_change(%{confirm_name: "Production"})

      # Confirm delete
      view
      |> element("#confirm-delete-btn")
      |> render_click()

      # impl-settings.DELETE.7: User is redirected to /p/:product_name after deletion
      assert_redirect(view, ~p"/t/#{team.name}/p/TestProduct")
    end

    # impl-settings.DRAWER.3
    test "drawer closes when clicking backdrop", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()
      assert has_element?(view, "#implementation-settings-drawer", "Production")

      # Close drawer via backdrop click (the backdrop is the first child div with phx-click="close")
      view
      |> element("#implementation-settings-drawer > div:first-child")
      |> render_click()

      # Drawer should be hidden
      refute has_element?(view, "#implementation-settings-drawer-panel.translate-x-0")
    end

    # impl-settings.DRAWER.3
    test "drawer closes when pressing Escape key", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()
      assert has_element?(view, "#implementation-settings-drawer", "Production")

      # Close drawer via Escape key
      view
      |> element("#implementation-settings-drawer")
      |> render_keydown(%{"key" => "Escape"})

      # Drawer should be hidden
      refute has_element?(view, "#implementation-settings-drawer-panel.translate-x-0")
    end

    # impl-settings.UNTRACK_BRANCH.4_2
    test "disabled delete button shows tooltip explaining it is the current feature's branch", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create branch for spec (this will be the current spec branch)
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # impl-settings.UNTRACK_BRANCH.4_2: Disabled delete button shows tooltip
      # The button should have a title attribute explaining it's the current feature's branch
      button = element(view, "#untrack-branch-btn-#{branch.id}")
      html = render(button)
      assert html =~ "current feature&#39;s branch"
      assert html =~ "cannot be untracked"
    end

    # impl-settings.UNTRACK_BRANCH.6_2
    # impl-settings.UNTRACK_BRANCH.6_3
    test "untrack modal shows warning text and cancel/untrack buttons", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on different branch
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch2,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click untrack button
      view
      |> element("#untrack-branch-btn-#{branch.id}")
      |> render_click()

      # impl-settings.UNTRACK_BRANCH.6_2: Confirmation modal explains refs may disappear
      assert has_element?(
               view,
               "#implementation-settings-drawer",
               "Code references from this branch will no longer appear"
             )

      # impl-settings.UNTRACK_BRANCH.6_3: Confirmation modal renders Cancel and Untrack buttons
      assert has_element?(view, "#cancel-untrack-btn", "Cancel")
      assert has_element?(view, "#confirm-untrack-btn", "Untrack")
    end

    # impl-settings.UNTRACK_BRANCH.9
    test "untrack modal explains user can re-track branch later without data loss", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on different branch
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch2,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click untrack button
      view
      |> element("#untrack-branch-btn-#{branch.id}")
      |> render_click()

      # impl-settings.UNTRACK_BRANCH.9: User can re-track the branch later without data loss
      assert has_element?(
               view,
               "#implementation-settings-drawer",
               "You can re-track this branch later without losing any data"
             )
    end

    # impl-settings.TRACK_BRANCH.2
    # impl-settings.TRACK_BRANCH.3_1
    # impl-settings.TRACK_BRANCH.4
    test "trackable branches exclude already tracked repos and show full repo_uri", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch
      tracked = branch_fixture(team, %{repo_uri: "github.com/org/tracked", branch_name: "main"})
      tracked_branch_fixture(impl, branch: tracked, repo_uri: tracked.repo_uri)

      # Create untracked branches
      _untracked1 =
        branch_fixture(team, %{repo_uri: "github.com/org/untracked1", branch_name: "develop"})

      _untracked2 =
        branch_fixture(team, %{repo_uri: "github.com/org/untracked2", branch_name: "feature"})

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: tracked,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click show track branch UI
      view
      |> element("#show-track-branch-btn")
      |> render_click()

      # impl-settings.TRACK_BRANCH.4: Each option displays full repo_uri plus branch name
      assert has_element?(view, "#implementation-settings-drawer", "github.com/org/untracked1")
      assert has_element?(view, "#implementation-settings-drawer", "github.com/org/untracked2")

      # impl-settings.TRACK_BRANCH.3_1: Excludes branches already tracked by this implementation
      refute has_element?(view, "#implementation-settings-drawer", "github.com/org/tracked")
    end

    # impl-settings.TRACK_BRANCH.3_2
    test "trackable branches exclude branches from other teams", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)

      # Create branch for other team
      other_team = team_fixture(%{name: "other-team"})

      _other_branch =
        branch_fixture(other_team, %{
          repo_uri: "github.com/other-team/repo",
          branch_name: "main"
        })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click show track branch UI
      view
      |> element("#show-track-branch-btn")
      |> render_click()

      # impl-settings.TRACK_BRANCH.3_2: List excludes branches for other teams
      refute has_element?(
               view,
               "#implementation-settings-drawer",
               "github.com/other-team/repo"
             )
    end

    # impl-settings.TRACK_BRANCH.5
    # impl-settings.TRACK_BRANCH.6
    # impl-settings.TRACK_BRANCH.7
    test "track branch UI shows save and cancel buttons with correct disabled state", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch for spec
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create trackable branch
      trackable =
        branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click show track branch UI
      view
      |> element("#show-track-branch-btn")
      |> render_click()

      # impl-settings.TRACK_BRANCH.5: Renders Save and Cancel buttons
      assert has_element?(view, "#cancel-track-branch-btn", "Cancel")
      assert has_element?(view, "#save-track-branch-btn")

      # impl-settings.TRACK_BRANCH.6: Save button is disabled when no branch is selected
      assert has_element?(view, "#save-track-branch-btn[disabled]")

      # Select a branch
      view
      |> element("[phx-click='select_branch_to_track'][phx-value-branch_id='#{trackable.id}']")
      |> render_click()

      # Save button should now be enabled
      refute has_element?(view, "#save-track-branch-btn[disabled]")

      # impl-settings.TRACK_BRANCH.7: Cancel button clears the current selection
      view
      |> element("#cancel-track-branch-btn")
      |> render_click()

      # Should be back to tracked branches list
      assert has_element?(view, "#show-track-branch-btn")
    end

    # impl-settings.TRACK_BRANCH.8
    # impl-settings.TRACK_BRANCH.9
    # impl-settings.TRACK_BRANCH.10
    test "tracking a branch updates UI immediately and refreshes trackable list", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch
      tracked = branch_fixture(team, %{repo_uri: "github.com/org/tracked", branch_name: "main"})
      tracked_branch_fixture(impl, branch: tracked, repo_uri: tracked.repo_uri)

      # Create branch to track
      to_track =
        branch_fixture(team, %{repo_uri: "github.com/org/to-track", branch_name: "develop"})

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: tracked,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click show track branch UI
      view
      |> element("#show-track-branch-btn")
      |> render_click()

      # Select the branch to track
      view
      |> element("[phx-click='select_branch_to_track'][phx-value-branch_id='#{to_track.id}']")
      |> render_click()

      # Save the tracking
      view
      |> element("#save-track-branch-btn")
      |> render_click()

      # impl-settings.TRACK_BRANCH.9: UI updates immediately to show the newly tracked branch
      assert has_element?(view, "#implementation-settings-drawer", "github.com/org/to-track")

      # impl-settings.TRACK_BRANCH.10: List of trackable branches refreshes to exclude the newly tracked branch
      # Click track branch UI again
      view
      |> element("#show-track-branch-btn")
      |> render_click()

      # Should not show the now-tracked branch
      refute has_element?(view, "#implementation-settings-drawer", "github.com/org/to-track")
    end

    # impl-settings.DELETE.4_3
    # impl-settings.DELETE.4_4
    # impl-settings.DELETE.4_5
    test "delete modal shows all warning text and required buttons", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click delete button
      view
      |> element("#delete-implementation-btn")
      |> render_click()

      # impl-settings.DELETE.4_3: Modal explains that all associated feature states and refs will be cleared
      assert has_element?(
               view,
               "#implementation-settings-drawer",
               "All feature states for this implementation"
             )

      assert has_element?(
               view,
               "#implementation-settings-drawer",
               "All code reference associations"
             )

      # impl-settings.DELETE.4_4: Modal explains that child implementations will lose inherited states and refs
      assert has_element?(
               view,
               "#implementation-settings-drawer",
               "Child implementations will lose inherited states and refs"
             )

      # impl-settings.DELETE.4_5: Modal renders Cancel and Delete buttons
      assert has_element?(view, "#cancel-delete-btn", "Cancel")
      assert has_element?(view, "#confirm-delete-btn", "Delete Implementation")
    end

    # feature-impl-view.MAIN.2: Button must display "Implementation Settings" text
    test "implementation settings button displays text label", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # feature-impl-view.MAIN.2: Renders an 'Implementation Settings' button with visible text
      assert has_element?(view, "#impl-settings-btn", "Implementation Settings")
    end

    # impl-settings.TRACK_BRANCH.5: Button label must be "Save"
    test "track branch save button displays 'Save' label", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch
      tracked = branch_fixture(team, %{repo_uri: "github.com/org/tracked", branch_name: "main"})
      tracked_branch_fixture(impl, branch: tracked, repo_uri: tracked.repo_uri)

      # Create trackable branch (not used directly but needed for the UI to show options)
      _trackable =
        branch_fixture(team, %{repo_uri: "github.com/org/trackable", branch_name: "develop"})

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: tracked,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer and track branch UI
      view |> element("#impl-settings-btn") |> render_click()
      view |> element("#show-track-branch-btn") |> render_click()

      # impl-settings.TRACK_BRANCH.5: Save button displays "Save" label
      assert has_element?(view, "#save-track-branch-btn", "Save")
    end

    # impl-settings.DELETE.1: Button label must be "Delete Implementation"
    test "delete implementation button displays 'Delete Implementation' label", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")
      create_spec_for_feature(team, product, "my-feature", for_implementation: impl)
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # impl-settings.DELETE.1: Renders a Delete Implementation button with visible text
      assert has_element?(view, "#delete-implementation-btn", "Delete Implementation")
    end

    # impl-settings.UNTRACK_BRANCH.8: Regression test - drawer stays open after untrack
    test "settings drawer remains open after untracking a branch", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on different branch so branch1 can be untracked
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: branch2,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Verify drawer is open by checking content is visible
      assert has_element?(view, "#implementation-settings-drawer", "Production")

      # Click untrack button
      view
      |> element("#untrack-branch-btn-#{branch.id}")
      |> render_click()

      # Confirm untrack - the render_click returns after handle_info completes
      view
      |> element("#confirm-untrack-btn")
      |> render_click()

      # impl-settings.UNTRACK_BRANCH.8: UI updates in-place with drawer remaining open
      # Verify drawer is still open: the drawer content should still be visible
      # and the branch should be removed from the list
      refute has_element?(view, "#implementation-settings-drawer", "github.com/org/repo1")
      # Verify the drawer panel is still visible by checking the translate-x-0 class
      # on the specific panel element (not just anywhere in the document)
      html = render(view)

      panel_open =
        html =~
          ~r/<div[^>]*id="implementation-settings-drawer-panel"[^>]*class="[^"]*translate-x-0[^"]*"/

      assert panel_open, "Drawer panel should still be visibly open after untrack"
    end

    # impl-settings.TRACK_BRANCH.9: Regression test - drawer stays open after track
    test "settings drawer remains open after tracking a branch", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branch
      tracked = branch_fixture(team, %{repo_uri: "github.com/org/tracked", branch_name: "main"})
      tracked_branch_fixture(impl, branch: tracked, repo_uri: tracked.repo_uri)

      # Create branch to track
      to_track =
        branch_fixture(team, %{repo_uri: "github.com/org/to-track", branch_name: "develop"})

      spec_fixture(product, %{
        feature_name: "my-feature",
        branch: tracked,
        requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
      })

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Verify drawer is open by checking content is visible
      assert has_element?(view, "#implementation-settings-drawer", "Production")

      # Click show track branch UI
      view
      |> element("#show-track-branch-btn")
      |> render_click()

      # Select the branch to track
      view
      |> element("[phx-click='select_branch_to_track'][phx-value-branch_id='#{to_track.id}']")
      |> render_click()

      # Save the tracking - render_click returns after all handlers complete
      view
      |> element("#save-track-branch-btn")
      |> render_click()

      # impl-settings.TRACK_BRANCH.9: UI updates in-place with drawer remaining open
      # Verify the newly tracked branch is now in the list
      assert has_element?(view, "#implementation-settings-drawer", "github.com/org/to-track")
      # Verify the drawer panel is still visible by checking the translate-x-0 class
      # on the specific panel element using regex to match the class within the panel div
      html = render(view)

      panel_open =
        html =~
          ~r/<div[^>]*id="implementation-settings-drawer-panel"[^>]*class="[^"]*translate-x-0[^"]*"/

      assert panel_open, "Drawer panel should still be visibly open after track"
    end

    # impl-settings.RENAME.8: Regression test - dropdown options refresh after rename
    test "implementation dropdown shows updated name after rename", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create two implementations that share the feature
      impl_a = create_implementation_for_product(product, name: "ImplA")

      impl_b =
        create_implementation_for_product(product, name: "ImplB")

      # Create a shared branch with the feature spec
      shared_branch =
        branch_fixture(team, %{repo_uri: "github.com/org/shared", branch_name: "main"})

      tracked_branch_fixture(impl_a, branch: shared_branch, repo_uri: shared_branch.repo_uri)
      tracked_branch_fixture(impl_b, branch: shared_branch, repo_uri: shared_branch.repo_uri)

      spec_fixture(product, %{
        feature_name: "shared-feature",
        branch: shared_branch,
        requirements: %{
          "shared-feature.COMP.1" => %{
            "definition" => "Shared req",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      slug_a = build_impl_slug(impl_a)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug_a}/f/shared-feature")

      # Verify initial state shows ImplA in dropdown
      assert has_element?(view, "#impl-popover", "ImplA")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Rename implementation
      view
      |> element("#rename-implementation-form")
      |> render_change(%{implementation: %{name: "RenamedImpl"}})

      view
      |> element("#rename-implementation-form")
      |> render_submit(%{implementation: %{name: "RenamedImpl"}})

      # Verify URL was patched
      assert_patch(view)

      # Verify implementation dropdown now shows the new name
      assert has_element?(view, "#impl-popover", "RenamedImpl")
      # And not the old name
      refute has_element?(view, "#impl-popover", "ImplA")
    end

    # impl-settings.UNTRACK_BRANCH.8: Regression test - page state refreshes after untrack
    test "refs counts refresh after untracking a branch", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product, name: "Production")

      # Create tracked branches
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/repo1", branch_name: "main"})
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2", branch_name: "develop"})

      tracked_branch_fixture(impl, branch: branch1, repo_uri: branch1.repo_uri)
      tracked_branch_fixture(impl, branch: branch2, repo_uri: branch2.repo_uri)

      # Create spec on branch1
      _spec =
        spec_fixture(product, %{
          feature_name: "my-feature",
          branch: branch1,
          requirements: %{"my-feature.COMP.1" => %{"definition" => "Test req"}}
        })

      # Create FeatureBranchRefs manually for both branches
      # (spec_impl_ref_fixture would create for all tracked branches which is not what we want here)
      Acai.Specs.FeatureBranchRef.changeset(
        %Acai.Specs.FeatureBranchRef{},
        %{
          feature_name: "my-feature",
          branch_id: branch1.id,
          refs: %{
            "my-feature.COMP.1" => [
              %{"path" => "lib/file1.ex:1", "is_test" => false}
            ]
          },
          commit: "abc123",
          pushed_at: DateTime.utc_now()
        }
      )
      |> Acai.Repo.insert!()

      Acai.Specs.FeatureBranchRef.changeset(
        %Acai.Specs.FeatureBranchRef{},
        %{
          feature_name: "my-feature",
          branch_id: branch2.id,
          refs: %{
            "my-feature.COMP.1" => [
              %{"path" => "lib/file2.ex:2", "is_test" => false}
            ]
          },
          commit: "abc123",
          pushed_at: DateTime.utc_now()
        }
      )
      |> Acai.Repo.insert!()

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Verify refs count shows 2 (from both branches)
      assert has_element?(view, "#requirement-row-my-feature-COMP-1 td:nth-child(4)", "2")

      # Open drawer
      view |> element("#impl-settings-btn") |> render_click()

      # Click untrack button for branch2
      view
      |> element("#untrack-branch-btn-#{branch2.id}")
      |> render_click()

      # Confirm untrack
      view
      |> element("#confirm-untrack-btn")
      |> render_click()

      # Verify refs count now shows 1 (only from branch1)
      assert has_element?(view, "#requirement-row-my-feature-COMP-1 td:nth-child(4)", "1")
    end
  end
end
