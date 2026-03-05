defmodule AcaiWeb.FeatureLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.AccountsFixtures
  import Acai.DataModelFixtures

  alias Acai.Specs
  alias Acai.Implementations

  # Helper to set up a team with an owner (the logged-in user)
  defp create_team_with_owner(user) do
    team = team_fixture()
    role = user_team_role_fixture(team, user, %{title: "owner"})
    {team, role}
  end

  # Helper to create a spec with a specific feature
  # Uses unique path to avoid unique constraint violation
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

  describe "unauthenticated access" do
    test "redirects to log-in", %{conn: conn} do
      team = team_fixture()
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/t/#{team.name}/f/some-feature")
      assert path == ~p"/users/log-in"
    end
  end

  describe "mount" do
    setup :register_and_log_in_user

    # feature-view.MAIN.1
    test "renders the feature name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_feature(team, "my-feature")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "h1", "my-feature")
    end

    # feature-view.ROUTING.1
    test "renders feature name with case-insensitive matching", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      # Create spec with feature name "MyFeature"
      create_spec_for_feature(team, "MyFeature")

      # Access with lowercase URL
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/myfeature")
      # Should display the actual feature name from database
      assert has_element?(view, "h1", "MyFeature")
    end

    # feature-view.MAIN.2
    test "renders feature description when present", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_feature(team, "my-feature", description: "A test feature description")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "p", "A test feature description")
    end

    # feature-view.MAIN.2
    test "does not render description when nil", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature", description: nil)

      # Update spec to have nil description
      Specs.update_spec(spec, %{feature_description: nil})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      # Should still render the page without error
      assert has_element?(view, "h1", "my-feature")
      # Description paragraph should not be present
      refute has_element?(view, "p", "Description")
    end

    # feature-view.MAIN.3
    test "renders implementation cards grid", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Debug: check if implementation exists
      assert impl.id != nil

      assert has_element?(view, "#implementations-grid")
      # The stream prefixes DOM ids with the stream name, so "implementations-" + "impl-#{uuid}"
      assert has_element?(view, "[id^='implementations-impl-']")
    end

    # feature-view.MAIN.3-1
    test "shows empty state when no implementations", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_feature(team, "my-feature")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, ".text-center", "No implementations found for this feature")
    end

    # feature-view.MAIN.4
    test "each card navigates to implementation view", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec, name: "MyImpl")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      expected_slug = Implementations.implementation_slug(impl)

      assert has_element?(view, "a[href='/t/#{team.name}/f/my-feature/i/#{expected_slug}']")
    end

    test "implementation card link uses sanitized slug for special characters", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec, name: "Deploy / Canary + EU-West 🚀")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      expected_slug = Implementations.implementation_slug(impl)

      assert expected_slug =~ ~r/^[a-z0-9-]+\+[0-9a-f]{32}$/
      assert has_element?(view, "a[href='/t/#{team.name}/f/my-feature/i/#{expected_slug}']")
    end
  end

  describe "implementation card" do
    setup :register_and_log_in_user

    # feature-view.IMPL_CARD.1
    test "shows implementation name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      create_implementation_for_spec(spec, name: "Production")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "Production")
    end

    # feature-view.IMPL_CARD.2
    test "shows tracked branch count", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      # Create tracked branches with unique repo_uris
      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo1")
      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo2")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "2 branches")
    end

    # feature-view.IMPL_CARD.2
    test "shows singular branch count", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "1 branch")
    end

    # feature-view.IMPL_CARD.3
    test "shows total requirements count", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      create_implementation_for_spec(spec)

      # Create requirements
      create_requirement_for_spec(spec)
      create_requirement_for_spec(spec)
      create_requirement_for_spec(spec)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "3 requirements")
    end

    # feature-view.IMPL_CARD.3
    test "shows singular requirement count", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      create_implementation_for_spec(spec)

      create_requirement_for_spec(spec)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "1 requirement")
    end

    # feature-view.IMPL_CARD.4
    test "progress bar shows correct proportions", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      # Create 4 requirements
      req1 = create_requirement_for_spec(spec)
      req2 = create_requirement_for_spec(spec)
      req3 = create_requirement_for_spec(spec)
      req4 = create_requirement_for_spec(spec)

      # 2 accepted, 1 completed, 1 null
      create_requirement_status(impl, req1, status: "accepted")
      create_requirement_status(impl, req2, status: "accepted")
      create_requirement_status(impl, req3, status: "completed")
      # req4 has no status (null)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Should show 3/4 complete
      assert has_element?(view, "#implementations-grid", "3/4")
    end

    # feature-view.IMPL_CARD.4-1
    test "progress bar green segment for accepted", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      req = create_requirement_for_spec(spec)
      create_requirement_status(impl, req, status: "accepted")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Should have green (success) segment
      assert has_element?(view, ".bg-success")
    end

    # feature-view.IMPL_CARD.4-2
    test "progress bar blue segment for completed", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      req = create_requirement_for_spec(spec)
      create_requirement_status(impl, req, status: "completed")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Should have blue (info) segment
      assert has_element?(view, ".bg-info")
    end

    # feature-view.IMPL_CARD.4-3
    test "progress bar gray segment for null status", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      impl = create_implementation_for_spec(spec)

      # Create requirement with no status
      create_requirement_for_spec(spec)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Should have gray segment (base-300)
      assert has_element?(view, ".bg-base-300")
    end
  end

  describe "routing" do
    setup :register_and_log_in_user

    # feature-view.ROUTING.1
    test "case-insensitive feature_name matching", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_feature(team, "MyFeature")

      # Test various case combinations
      for feature_name <- ["MyFeature", "myfeature", "MYFEATURE", "Myfeature"] do
        {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/#{feature_name}")
        assert has_element?(view, "h1", "MyFeature")
      end
    end

    # feature-view.ROUTING.2
    test "redirects to team page when feature not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      # Don't create any specs for this feature

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/t/#{team.name}/f/NonExistentFeature")

      assert redirect_to == ~p"/t/#{team.name}"
    end

    # feature-view.ROUTING.2
    test "shows flash message when feature not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)

      assert {:error, {:live_redirect, %{flash: flash}}} =
               live(conn, ~p"/t/#{team.name}/f/NonExistentFeature")

      assert flash["error"] == "Feature not found"
    end
  end

  describe "data isolation" do
    setup :register_and_log_in_user

    test "only shows implementations for the correct team", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      create_implementation_for_spec(spec, name: "MyImpl")

      # Create another team with a different user
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      other_spec = create_spec_for_feature(other_team, "my-feature")
      create_implementation_for_spec(other_spec, name: "OtherImpl")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      # Should only show implementations from the current team
      assert has_element?(view, "#implementations-grid", "MyImpl")
      refute has_element?(view, "#implementations-grid", "OtherImpl")
    end

    test "only shows active implementations", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "my-feature")
      create_implementation_for_spec(spec, name: "ActiveImpl", is_active: true)
      create_implementation_for_spec(spec, name: "InactiveImpl", is_active: false)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "ActiveImpl")
      refute has_element?(view, "#implementations-grid", "InactiveImpl")
    end
  end

  describe "specs context functions" do
    setup :register_and_log_in_user

    test "get_specs_by_feature_name returns correct feature and specs", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      spec1 = create_spec_for_feature(team, "MyFeature")
      spec2 = create_spec_for_feature(team, "MyFeature", product: "OtherProduct")

      {feature_name, specs} = Specs.get_specs_by_feature_name(team, "myfeature")
      assert feature_name == "MyFeature"
      assert length(specs) == 2
      assert Enum.any?(specs, &(&1.id == spec1.id))
      assert Enum.any?(specs, &(&1.id == spec2.id))
    end

    test "get_specs_by_feature_name returns nil for non-existent feature", %{user: user} do
      {team, _role} = create_team_with_owner(user)

      result = Specs.get_specs_by_feature_name(team, "nonexistent")
      assert result == nil
    end
  end

  describe "implementations context functions" do
    setup :register_and_log_in_user

    test "list_active_implementations_for_specs returns correct implementations", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      spec1 = create_spec_for_feature(team, "feature-1")
      spec2 = create_spec_for_feature(team, "feature-2")
      impl1 = create_implementation_for_spec(spec1, is_active: true)
      impl2 = create_implementation_for_spec(spec2, is_active: true)
      create_implementation_for_spec(spec1, is_active: false)

      impls = Implementations.list_active_implementations_for_specs([spec1, spec2])
      assert length(impls) == 2
      assert Enum.any?(impls, &(&1.id == impl1.id))
      assert Enum.any?(impls, &(&1.id == impl2.id))
    end

    test "count_tracked_branches returns correct count", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "feature-1")
      impl = create_implementation_for_spec(spec)

      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo1")
      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo2")
      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo3")

      count = Implementations.count_tracked_branches(impl)
      assert count == 3
    end

    test "get_requirement_status_counts returns correct counts", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_feature(team, "feature-1")
      impl = create_implementation_for_spec(spec)

      # Create 5 requirements
      req1 = create_requirement_for_spec(spec)
      req2 = create_requirement_for_spec(spec)
      req3 = create_requirement_for_spec(spec)
      req4 = create_requirement_for_spec(spec)
      req5 = create_requirement_for_spec(spec)

      # 2 accepted, 1 completed, 2 null
      create_requirement_status(impl, req1, status: "accepted")
      create_requirement_status(impl, req2, status: "accepted")
      create_requirement_status(impl, req3, status: "completed")
      # req4 and req5 have no status

      counts = Implementations.get_requirement_status_counts(impl, 5)
      assert counts.accepted == 2
      assert counts.completed == 1
      assert counts.null == 2
    end
  end
end
