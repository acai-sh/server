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
  defp create_spec_for_feature(_team, product, feature_name, opts \\ []) do
    unique_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

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

    spec_fixture(product, %{
      feature_name: feature_name,
      feature_description: Keyword.get(opts, :description, "Description for #{feature_name}"),
      path: "features/#{feature_name}-#{unique_suffix}/feature.yaml",
      repo_uri: "github.com/test/repo-#{unique_suffix}",
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
      slug = "some-impl+018f1a2b3c4d5e6f7a8b9c0d1e2f3a4b"

      {:error, {:redirect, %{to: path}}} =
        live(conn, ~p"/t/#{team.name}/i/#{slug}/f/some-feature")

      assert path == ~p"/users/log-in"
    end
  end

  describe "mount" do
    setup :register_and_log_in_user

    # implementation-view.MAIN.1
    test "renders the implementation name as page title", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product, name: "Production")
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")
      assert has_element?(view, "h1", "Production")
    end

    # implementation-view.MAIN.2
    test "renders breadcrumb with overview, product, and feature links", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product, name: "Production")
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
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product, name: "Production")
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")
      assert has_element?(view, "h1", "Production")
    end

    # implementation-view.ROUTING.2-1
    test "slug name portion is cosmetic and ignored", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product, name: "Production")

      # Build slug with wrong name but correct UUID
      uuid_string = impl.id |> to_string()
      uuid_without_dashes = String.replace(uuid_string, "-", "")
      wrong_name_slug = "wrong-name+#{uuid_without_dashes}"

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{wrong_name_slug}/f/my-feature")
      # Should still show the correct implementation name
      assert has_element?(view, "h1", "Production")
    end

    test "uses URL-safe slug when implementation name has special characters", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product, name: "QA / Canary + EU-West 🚀")

      slug = build_impl_slug(impl)

      assert slug =~ ~r/^[a-z0-9-]+\+[0-9a-f]{32}$/

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")
      assert has_element?(view, "h1", "QA / Canary + EU-West 🚀")
    end

    # implementation-view.ROUTING.3
    test "redirects to feature view if implementation not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")

      # Use a non-existent UUID
      fake_slug = "some-impl+018f1a2b3c4d5e6f7a8b9c0d1e2f3a4b"

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/t/#{team.name}/i/#{fake_slug}/f/my-feature")

      assert redirect_to == ~p"/t/#{team.name}/f/my-feature"
    end

    # implementation-view.ROUTING.3
    test "shows flash message when implementation not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")

      fake_slug = "some-impl+018f1a2b3c4d5e6f7a8b9c0d1e2f3a4b"

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
      _spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

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
      spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)
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
      spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)
      create_spec_impl_state(spec, impl, status: "completed")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, ".bg-info[title='my-feature.COMP.1']")
    end

    # implementation-view.REQ_COVERAGE.2-3
    test "gray chip for null status", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)
      # No status created

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, ".bg-base-300[title='my-feature.COMP.1']")
    end

    # implementation-view.REQ_COVERAGE.3
    test "clicking chip opens requirement details drawer", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

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
      spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)
      _branch = tracked_branch_fixture(impl)

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
      spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)
      # Need tracked branch to store refs
      _tracked_branch = tracked_branch_fixture(impl)

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
      spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

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
      spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)
      # Need tracked branch to store refs
      _tracked_branch = tracked_branch_fixture(impl)

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
      spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

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
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

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
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo1", branch_name: "main")
      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo2", branch_name: "develop")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, "div", "github.com/org/repo1")
      assert has_element?(view, "div", "main")
      assert has_element?(view, "div", "github.com/org/repo2")
      assert has_element?(view, "div", "develop")
    end

    # implementation-view.LINKED_BRANCHES.2
    test "each entry shows repo_uri and branch_name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo", branch_name: "feature-branch")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, "div", "github.com/org/repo")
      assert has_element?(view, "div", "feature-branch")
    end

    test "shows empty state when no tracked branches", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      assert has_element?(view, "div", "No tracked branches")
    end
  end

  describe "REQ_LIST - requirements table" do
    setup :register_and_log_in_user

    # implementation-view.REQ_LIST.1
    test "renders table with correct columns", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      _spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Check table headers
      assert has_element?(view, "th", "ACID")
      assert has_element?(view, "th", "Status")
      assert has_element?(view, "th", "Definition")
      assert has_element?(view, "th", "Refs")
      assert has_element?(view, "th", "Tests")

      # Check row content
      assert has_element?(view, "td", "my-feature.COMP.1")
      assert has_element?(view, "td", "Test requirement 1 for my-feature")
    end

    # implementation-view.REQ_LIST.2
    test "Refs column shows count of non-test references", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)
      # Need tracked branch to store refs
      _tracked_branch = tracked_branch_fixture(impl)

      # Add non-test references via spec_impl_refs
      create_spec_impl_ref(spec, impl,
        refs: %{
          "my-feature.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "lib/file1.ex:1",
              "loc" => "1:1",
              "is_test" => false
            },
            %{
              "repo" => "github.com/org/repo",
              "path" => "lib/file2.ex:2",
              "loc" => "2:1",
              "is_test" => false
            }
          ]
        }
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Should show count 2 in Refs column
      html = render(view)
      assert html =~ ">2<"
    end

    # implementation-view.REQ_LIST.3
    test "Tests column shows count of test references", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      spec = create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)
      # Need tracked branch to store refs
      _tracked_branch = tracked_branch_fixture(impl)

      # Add test references via spec_impl_refs
      create_spec_impl_ref(spec, impl,
        refs: %{
          "my-feature.COMP.1" => [
            %{
              "repo" => "github.com/org/repo",
              "path" => "test/file1_test.ex:1",
              "loc" => "1:1",
              "is_test" => true
            },
            %{
              "repo" => "github.com/org/repo",
              "path" => "test/file2_test.ex:2",
              "loc" => "2:1",
              "is_test" => true
            },
            %{
              "repo" => "github.com/org/repo",
              "path" => "test/file3_test.ex:3",
              "loc" => "3:1",
              "is_test" => true
            }
          ]
        }
      )

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Should show count 3 in Tests column
      html = render(view)
      assert html =~ ">3<"
    end

    # implementation-view.REQ_LIST.4
    test "all columns are sortable", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # All headers should be clickable for sorting
      assert has_element?(view, "th[phx-click='sort'][phx-value-by='acid']")
      assert has_element?(view, "th[phx-click='sort'][phx-value-by='status']")
      assert has_element?(view, "th[phx-click='sort'][phx-value-by='definition']")
      assert has_element?(view, "th[phx-click='sort'][phx-value-by='refs']")
      assert has_element?(view, "th[phx-click='sort'][phx-value-by='tests']")
    end

    # implementation-view.REQ_LIST.4-1
    test "default sort is ACID ascending", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create spec with specific requirements order
      requirements = %{
        "my-feature.COMP.3" => %{
          "definition" => "Req 3",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "my-feature.COMP.1" => %{
          "definition" => "Req 1",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "my-feature.COMP.2" => %{
          "definition" => "Req 2",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      create_spec_for_feature(team, product, "my-feature", requirements: requirements)
      impl = create_implementation_for_product(product)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Get the order of ACIDs in the table
      html = render(view)

      # Find positions of each ACID in the HTML
      pos1 = :binary.match(html, "my-feature.COMP.1") |> elem(0)
      pos2 = :binary.match(html, "my-feature.COMP.2") |> elem(0)
      pos3 = :binary.match(html, "my-feature.COMP.3") |> elem(0)

      # ACID 1 should come before ACID 2, which should come before ACID 3
      assert pos1 < pos2
      assert pos2 < pos3
    end

    # implementation-view.REQ_LIST.4
    test "clicking header toggles sort direction", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Click on ACID header to sort descending
      view
      |> element("th[phx-value-by='acid']")
      |> render_click()

      html = render(view)

      # Now ACID 2 should come before ACID 1 (descending order)
      pos1 = :binary.match(html, "my-feature.COMP.1") |> elem(0)
      pos2 = :binary.match(html, "my-feature.COMP.2") |> elem(0)

      assert pos2 < pos1
    end

    # implementation-view.REQ_LIST.5
    test "clicking row opens requirement details drawer", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

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
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product, name: "MyImpl")

      # Create another team with different implementation
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      other_product = create_product(other_team, "TestProduct")
      create_spec_for_feature(other_team, other_product, "my-feature")
      create_implementation_for_product(other_product, name: "OtherImpl")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Should show the correct implementation
      assert has_element?(view, "h1", "MyImpl")
      refute has_element?(view, "h1", "OtherImpl")
    end

    test "redirects when trying to access other team's implementation", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")

      # Create another team with implementation
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      other_product = create_product(other_team, "TestProduct")
      create_spec_for_feature(other_team, other_product, "other-feature")
      other_impl = create_implementation_for_product(other_product, name: "OtherImpl")

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

      requirements = %{
        "my-feature.COMP.1" => %{
          "definition" => "My test requirement definition",
          "note" => "Test note",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      create_spec_for_feature(team, product, "my-feature", requirements: requirements)
      impl = create_implementation_for_product(product)

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
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer
      view |> render_click("open_drawer", %{"acid" => "my-feature.COMP.1"})

      # Close drawer
      view
      |> element("button[aria-label='Close drawer']")
      |> render_click()

      # Drawer should be hidden
      refute has_element?(view, ".translate-x-0")
    end

    test "same requirement can be opened multiple times", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/my-feature")

      # Open drawer for first time
      view |> render_click("open_drawer", %{"acid" => "my-feature.COMP.1"})
      assert has_element?(view, ".translate-x-0")
      assert has_element?(view, "h2", "my-feature.COMP.1")

      # Close drawer
      view
      |> element("button[aria-label='Close drawer']")
      |> render_click()

      refute has_element?(view, ".translate-x-0")

      # Open same requirement again - should work
      view |> render_click("open_drawer", %{"acid" => "my-feature.COMP.1"})
      assert has_element?(view, ".translate-x-0")
      assert has_element?(view, "h2", "my-feature.COMP.1")
    end
  end
end
