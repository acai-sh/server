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

  # Helper to create a spec with a specific feature
  defp create_spec_for_feature(team, feature_name, opts \\ []) do
    unique_id = System.unique_integer([:positive])

    spec_fixture(team, %{
      feature_product: Keyword.get(opts, :product, "TestProduct"),
      feature_name: feature_name,
      feature_description: Keyword.get(opts, :description, "Description for #{feature_name}"),
      path: "features/#{feature_name}-#{unique_id}/feature.yaml"
    })
  end

  # Helper to create an implementation for a spec
  defp create_implementation_for_spec(spec, opts \\ []) do
    implementation_fixture(spec, %{
      name: Keyword.get(opts, :name, "Impl-#{System.unique_integer([:positive])}"),
      is_active: Keyword.get(opts, :is_active, true)
    })
  end

  # Helper to create a requirement for a spec
  defp create_requirement_for_spec(spec, opts \\ []) do
    unique_id = System.unique_integer([:positive])

    requirement_fixture(spec, %{
      group_key: Keyword.get(opts, :group_key, "COMP"),
      group_type: Keyword.get(opts, :group_type, :COMPONENT),
      local_id: Keyword.get(opts, :local_id, "#{unique_id}"),
      definition: Keyword.get(opts, :definition, "A requirement"),
      feature_name: spec.feature_name
    })
  end

  # Helper to create a requirement status
  defp create_requirement_status(impl, requirement, opts \\ []) do
    requirement_status_fixture(impl, requirement, %{
      status: Keyword.get(opts, :status, nil),
      is_active: true,
      last_seen_commit: "abc123"
    })
  end

  # Helper to build slug for an implementation
  defp build_impl_slug(impl) do
    Implementations.implementation_slug(impl)
  end

  # Helper to create a code reference
  defp create_code_reference(requirement, branch, opts \\ []) do
    code_reference_fixture(requirement, branch, %{
      path: Keyword.get(opts, :path, "lib/my_app/my_module.ex:42"),
      is_test: Keyword.get(opts, :is_test, false)
    })
  end

  describe "unauthenticated access" do
    test "redirects to log-in", %{conn: conn} do
      team = team_fixture()
      slug = "some-impl+018f1a2b3c4d5e6f7a8b9c0d1e2f3a4b"

      {:error, {:redirect, %{to: path}}} =
        live(conn, ~p"/t/#{team.name}/f/some-feature/i/#{slug}")

      assert path == ~p"/users/log-in"
    end
  end

  describe "mount" do
    setup :register_and_log_in_user

    # implementation-view.MAIN.1
    test "renders the implementation name as page title", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec, name: "Production")
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")
      assert has_element?(view, "h1", "Production")
    end

    # implementation-view.MAIN.2
    test "renders breadcrumb with team, product, and feature links", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature", product: "MyProduct")
      impl = create_implementation_for_spec(spec, name: "Production")
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Check breadcrumb links exist
      assert has_element?(view, "a[href='/t/#{team.name}']", team.name)
      assert has_element?(view, "a[href='/t/#{team.name}/p/MyProduct']", "MyProduct")
      assert has_element?(view, "a[href='/t/#{team.name}/f/my-feature']", "my-feature")
    end

    # implementation-view.ROUTING.2
    test "parses slug and finds implementation by UUID", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec, name: "Production")
      slug = build_impl_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")
      assert has_element?(view, "h1", "Production")
    end

    # implementation-view.ROUTING.2-1
    test "slug name portion is cosmetic and ignored", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec, name: "Production")

      # Build slug with wrong name but correct UUID
      uuid_string = impl.id |> to_string()
      uuid_without_dashes = String.replace(uuid_string, "-", "")
      wrong_name_slug = "wrong-name+#{uuid_without_dashes}"

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{wrong_name_slug}")
      # Should still show the correct implementation name
      assert has_element?(view, "h1", "Production")
    end

    test "uses URL-safe slug when implementation name has special characters", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec, name: "QA / Canary + EU-West 🚀")

      slug = build_impl_slug(impl)

      assert slug =~ ~r/^[a-z0-9-]+\+[0-9a-f]{32}$/

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")
      assert has_element?(view, "h1", "QA / Canary + EU-West 🚀")
    end

    # implementation-view.ROUTING.3
    test "redirects to feature view if implementation not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_feature(team, "my-feature")

      # Use a non-existent UUID
      fake_slug = "some-impl+018f1a2b3c4d5e6f7a8b9c0d1e2f3a4b"

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{fake_slug}")

      assert redirect_to == ~p"/t/#{team.name}/f/my-feature"
    end

    # implementation-view.ROUTING.3
    test "shows flash message when implementation not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_feature(team, "my-feature")

      fake_slug = "some-impl+018f1a2b3c4d5e6f7a8b9c0d1e2f3a4b"

      assert {:error, {:live_redirect, %{flash: flash}}} =
               live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{fake_slug}")

      assert flash["error"] == "Implementation not found"
    end
  end

  describe "REQ_COVERAGE - requirements coverage grid" do
    setup :register_and_log_in_user

    # implementation-view.REQ_COVERAGE.1
    test "renders one chip per requirement ordered by ACID", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      # Create requirements with specific ACIDs
      req1 = create_requirement_for_spec(spec, group_key: "COMP", local_id: "2")
      req2 = create_requirement_for_spec(spec, group_key: "COMP", local_id: "1")
      req3 = create_requirement_for_spec(spec, group_key: "COMP", local_id: "3")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Should have chips for all requirements
      assert has_element?(view, "div[title='#{req1.acid}']")
      assert has_element?(view, "div[title='#{req2.acid}']")
      assert has_element?(view, "div[title='#{req3.acid}']")
    end

    # implementation-view.REQ_COVERAGE.2-1
    test "green chip for accepted status", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      req = create_requirement_for_spec(spec)
      create_requirement_status(impl, req, status: "accepted")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      assert has_element?(view, ".bg-success[title='#{req.acid}']")
    end

    # implementation-view.REQ_COVERAGE.2-2
    test "blue chip for completed status", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      req = create_requirement_for_spec(spec)
      create_requirement_status(impl, req, status: "completed")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      assert has_element?(view, ".bg-info[title='#{req.acid}']")
    end

    # implementation-view.REQ_COVERAGE.2-3
    test "gray chip for null status", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      req = create_requirement_for_spec(spec)
      # No status created

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      assert has_element?(view, ".bg-base-300[title='#{req.acid}']")
    end

    # implementation-view.REQ_COVERAGE.3
    test "clicking chip opens requirement details drawer", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      req = create_requirement_for_spec(spec)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Click on the chip using the phx-click event
      view |> render_click("open_drawer", %{"requirement_id" => req.id})

      # Drawer should be visible
      assert has_element?(view, "#requirement-details-drawer")
    end
  end

  describe "TEST_COVERAGE - test coverage grid" do
    setup :register_and_log_in_user

    # implementation-view.TEST_COVERAGE.1
    test "renders one chip per requirement ordered by ACID", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      branch = tracked_branch_fixture(impl)

      req1 = create_requirement_for_spec(spec, group_key: "COMP", local_id: "2")
      req2 = create_requirement_for_spec(spec, group_key: "COMP", local_id: "1")

      # Add test references
      create_code_reference(req1, branch, is_test: true)
      create_code_reference(req2, branch, is_test: true)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      assert has_element?(view, "div[title*='#{req1.acid}']")
      assert has_element?(view, "div[title*='#{req2.acid}']")
    end

    # implementation-view.TEST_COVERAGE.2-1
    test "green chip when test references exist", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      branch = tracked_branch_fixture(impl)
      req = create_requirement_for_spec(spec)

      # Add test reference
      create_code_reference(req, branch, is_test: true)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Should have green background for test coverage
      assert has_element?(view, ".bg-success[title*='#{req.acid}']")
    end

    # implementation-view.TEST_COVERAGE.2-2
    test "gray chip when no test references", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      branch = tracked_branch_fixture(impl)
      req = create_requirement_for_spec(spec)

      # Add non-test reference only
      create_code_reference(req, branch, is_test: false)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Should have gray background for no test coverage
      assert has_element?(view, ".bg-base-300[title*='#{req.acid}']")
    end

    # implementation-view.TEST_COVERAGE.3
    test "displays count of test references on green chips", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      branch = tracked_branch_fixture(impl)
      req = create_requirement_for_spec(spec)

      # Add multiple test references
      create_code_reference(req, branch, is_test: true, path: "test1.ex:1")
      create_code_reference(req, branch, is_test: true, path: "test2.ex:2")
      create_code_reference(req, branch, is_test: true, path: "test3.ex:3")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Should show count 3 inside the chip
      assert has_element?(view, ".bg-success", "3")
    end

    # implementation-view.TEST_COVERAGE.4
    test "clicking chip opens requirement details drawer", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      branch = tracked_branch_fixture(impl)
      req = create_requirement_for_spec(spec)
      create_code_reference(req, branch, is_test: true)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Click on the test coverage chip using the phx-click event
      view |> render_click("open_drawer", %{"requirement_id" => req.id})

      # Drawer should be visible
      assert has_element?(view, "#requirement-details-drawer")
    end
  end

  describe "CANONICAL_SPEC - canonical spec link" do
    setup :register_and_log_in_user

    # implementation-view.CANONICAL_SPEC.1
    test "renders feature name as link to feature view", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      assert has_element?(view, "a[href='/t/#{team.name}/f/my-feature']", "my-feature")
    end
  end

  describe "LINKED_BRANCHES - tracked branches list" do
    setup :register_and_log_in_user

    # implementation-view.LINKED_BRANCHES.1
    test "renders list of tracked branches", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo1", branch_name: "main")
      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo2", branch_name: "develop")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      assert has_element?(view, "div", "github.com/org/repo1")
      assert has_element?(view, "div", "main")
      assert has_element?(view, "div", "github.com/org/repo2")
      assert has_element?(view, "div", "develop")
    end

    # implementation-view.LINKED_BRANCHES.2
    test "each entry shows repo_uri and branch_name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo", branch_name: "feature-branch")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      assert has_element?(view, "div", "github.com/org/repo")
      assert has_element?(view, "div", "feature-branch")
    end

    test "shows empty state when no tracked branches", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      assert has_element?(view, "div", "No tracked branches")
    end
  end

  describe "REQ_LIST - requirements table" do
    setup :register_and_log_in_user

    # implementation-view.REQ_LIST.1
    test "renders table with correct columns", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      req = create_requirement_for_spec(spec, definition: "Test requirement")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Check table headers
      assert has_element?(view, "th", "ACID")
      assert has_element?(view, "th", "Status")
      assert has_element?(view, "th", "Definition")
      assert has_element?(view, "th", "Refs")
      assert has_element?(view, "th", "Tests")

      # Check row content
      assert has_element?(view, "td", req.acid)
      assert has_element?(view, "td", "Test requirement")
    end

    # implementation-view.REQ_LIST.2
    test "Refs column shows count of non-test references", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      branch = tracked_branch_fixture(impl)
      req = create_requirement_for_spec(spec)

      # Add non-test references
      create_code_reference(req, branch, is_test: false, path: "lib/file1.ex:1")
      create_code_reference(req, branch, is_test: false, path: "lib/file2.ex:2")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Should show count 2 in Refs column
      html = render(view)
      assert html =~ ">2<"
    end

    # implementation-view.REQ_LIST.3
    test "Tests column shows count of test references", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      branch = tracked_branch_fixture(impl)
      req = create_requirement_for_spec(spec)

      # Add test references
      create_code_reference(req, branch, is_test: true, path: "test/file1_test.ex:1")
      create_code_reference(req, branch, is_test: true, path: "test/file2_test.ex:2")
      create_code_reference(req, branch, is_test: true, path: "test/file3_test.ex:3")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Should show count 3 in Tests column
      html = render(view)
      assert html =~ ">3<"
    end

    # implementation-view.REQ_LIST.4
    test "all columns are sortable", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      create_requirement_for_spec(spec)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

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
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      # Create requirements with different ACIDs
      req1 = create_requirement_for_spec(spec, group_key: "COMP", local_id: "3")
      req2 = create_requirement_for_spec(spec, group_key: "COMP", local_id: "1")
      req3 = create_requirement_for_spec(spec, group_key: "COMP", local_id: "2")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Get the order of ACIDs in the table
      html = render(view)

      # Find positions of each ACID in the HTML
      pos1 = :binary.match(html, req1.acid) |> elem(0)
      pos2 = :binary.match(html, req2.acid) |> elem(0)
      pos3 = :binary.match(html, req3.acid) |> elem(0)

      # ACID 1 should come before ACID 2, which should come before ACID 3
      assert pos2 < pos3
      assert pos3 < pos1
    end

    # implementation-view.REQ_LIST.4
    test "clicking header toggles sort direction", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      req1 = create_requirement_for_spec(spec, group_key: "COMP", local_id: "1")
      req2 = create_requirement_for_spec(spec, group_key: "COMP", local_id: "2")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Click on ACID header to sort descending
      view
      |> element("th[phx-value-by='acid']")
      |> render_click()

      html = render(view)

      # Now ACID 2 should come before ACID 1
      pos1 = :binary.match(html, req1.acid) |> elem(0)
      pos2 = :binary.match(html, req2.acid) |> elem(0)

      assert pos2 < pos1
    end

    # implementation-view.REQ_LIST.5
    test "clicking row opens requirement details drawer", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      req = create_requirement_for_spec(spec)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Click on the table row
      view
      |> element("tr[phx-value-requirement_id='#{req.id}']")
      |> render_click()

      # Drawer should be visible
      assert has_element?(view, "#requirement-details-drawer")
    end
  end

  describe "data isolation" do
    setup :register_and_log_in_user

    test "only shows data for the correct team", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec, name: "MyImpl")

      # Create another team with different implementation
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      other_spec = create_spec_for_feature(other_team, "my-feature")
      create_implementation_for_spec(other_spec, name: "OtherImpl")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Should show the correct implementation
      assert has_element?(view, "h1", "MyImpl")
      refute has_element?(view, "h1", "OtherImpl")
    end

    test "redirects when trying to access other team's implementation", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_feature(team, "my-feature")

      # Create another team with implementation
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      other_spec = create_spec_for_feature(other_team, "other-feature")
      other_impl = create_implementation_for_spec(other_spec, name: "OtherImpl")

      # Try to access other team's implementation via our team's URL
      slug = build_impl_slug(other_impl)

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      assert redirect_to == ~p"/t/#{team.name}/f/my-feature"
    end
  end

  describe "requirement details drawer integration" do
    setup :register_and_log_in_user

    test "drawer shows requirement details when opened", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      req = create_requirement_for_spec(spec, definition: "My test requirement definition")

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Open drawer using the phx-click event
      view |> render_click("open_drawer", %{"requirement_id" => req.id})

      # Should show requirement details
      assert has_element?(view, "#requirement-details-drawer")
      assert has_element?(view, "h2", req.acid)
      assert has_element?(view, "p", "My test requirement definition")
    end

    test "drawer can be closed", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)
      req = create_requirement_for_spec(spec)

      slug = build_impl_slug(impl)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature/i/#{slug}")

      # Open drawer
      view |> render_click("open_drawer", %{"requirement_id" => req.id})

      # Close drawer
      view
      |> element("button[aria-label='Close drawer']")
      |> render_click()

      # Drawer should be hidden
      refute has_element?(view, ".translate-x-0")
    end
  end
end
