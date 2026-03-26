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

  # data-model.PRODUCTS: Create product as first-class entity
  defp create_product(team, name) do
    product_fixture(team, %{name: name, is_active: true})
  end

  # data-model.SPECS: Create spec for a product with JSONB requirements
  # Options:
  #   - :requirements - Custom requirements map (defaults to 2 standard requirements)
  #   - :branch - Pre-created branch to use (if not provided, creates new branch)
  #   - :repo_uri - Repo URI for branch (required when passing :branch)
  defp create_spec_for_feature(_team, product, feature_name, opts \\ []) do
    unique_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    # data-model.SPECS.13: Requirements stored as JSONB
    requirements =
      Keyword.get(opts, :requirements, %{
        "#{feature_name}.COMP.1" => %{
          "requirement" => "Test requirement 1",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "#{feature_name}.COMP.2" => %{
          "requirement" => "Test requirement 2",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      })

    attrs = %{
      feature_name: feature_name,
      feature_description: Keyword.get(opts, :description, "Description for #{feature_name}"),
      feature_version: Keyword.get(opts, :version, "1.0.0"),
      path: "features/#{feature_name}-#{unique_suffix}/feature.yaml",
      repo_uri: "github.com/test/repo-#{unique_suffix}",
      requirements: requirements
    }

    # Allow passing :branch and :repo_uri to link spec to existing branch
    # This is important for tests where implementations track specific branches
    attrs =
      if opts[:branch] do
        attrs
        |> Map.put(:branch, opts[:branch])
        |> Map.put(:repo_uri, opts[:repo_uri] || opts[:branch].repo_uri)
      else
        attrs
      end

    spec_fixture(product, attrs)
  end

  # data-model.IMPLS: Create implementation for a product
  defp create_implementation_for_product(product, opts \\ []) do
    attrs = %{
      name: Keyword.get(opts, :name, "Impl-#{System.unique_integer([:positive])}"),
      is_active: Keyword.get(opts, :is_active, true)
    }

    # Only add parent_implementation_id if it's provided
    attrs =
      if opts[:parent_implementation_id] do
        Map.put(attrs, :parent_implementation_id, opts[:parent_implementation_id])
      else
        attrs
      end

    implementation_fixture(product, attrs)
  end

  # data-model.FEATURE_IMPL_STATES: Create feature_impl_state with JSONB states
  defp create_spec_impl_state(spec, implementation, opts) do
    acid_prefix = spec.feature_name <> ".COMP"

    states =
      Keyword.get(opts, :states, %{
        "#{acid_prefix}.1" => %{
          "status" => Keyword.get(opts, :status, "pending"),
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      })

    spec_impl_state_fixture(spec, implementation, %{states: states})
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
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      # Feature name is in the dropdown button
      assert has_element?(view, "button", "my-feature")
    end

    # feature-view.ROUTING.1
    test "renders feature name with case-insensitive matching", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "MyFeature")

      # Access with lowercase URL
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/myfeature")
      # Should display the actual feature name from database
      assert has_element?(view, "button", "MyFeature")
    end

    # feature-view.MAIN.2
    test "renders page title", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      create_spec_for_feature(team, product, "my-feature",
        description: "A test feature description"
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      # Page title is in the text spans around the dropdown
      html = render(view)
      assert html =~ "Overview of the"
      assert html =~ "my-feature"
    end

    # feature-view.MAIN.2
    test "does not render description when nil", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      spec = create_spec_for_feature(team, product, "my-feature", description: nil)

      # Update spec to have nil description
      Specs.update_spec(spec, %{feature_description: nil})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      # Should still render the page without error
      assert has_element?(view, "button", "my-feature")
      # Description paragraph should not be present
      refute has_element?(view, "p", "Description")
    end

    # feature-view.MAIN.3
    test "renders implementation cards grid", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create a shared branch first
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo", branch_name: "main"})

      # Create implementation
      impl = create_implementation_for_product(product, name: "Impl-1")

      # Track the shared branch
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on the same branch so implementation can resolve it
      create_spec_for_feature(team, product, "my-feature",
        requirements: %{
          "my-feature.COMP.1" => %{"requirement" => "Req 1"}
        },
        branch: branch,
        repo_uri: branch.repo_uri
      )

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
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, ".text-center", "No implementations found for this feature")
    end

    # feature-view.MAIN.4
    test "each card navigates to implementation view", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create a shared branch first
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo", branch_name: "main"})

      # Create implementation
      impl = create_implementation_for_product(product, name: "MyImpl")

      # Track the shared branch
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on the same branch so implementation can resolve it
      create_spec_for_feature(team, product, "my-feature",
        requirements: %{
          "my-feature.COMP.1" => %{"requirement" => "Req 1"}
        },
        branch: branch,
        repo_uri: branch.repo_uri
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      expected_slug = Implementations.implementation_slug(impl)

      assert has_element?(view, "a[href='/t/#{team.name}/i/#{expected_slug}/f/my-feature']")
    end

    test "implementation card link uses sanitized slug for special characters", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create a shared branch first
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo", branch_name: "main"})

      # Create implementation with special characters in name
      impl = create_implementation_for_product(product, name: "Deploy / Canary + EU-West 🚀")

      # Track the shared branch
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on the same branch so implementation can resolve it
      create_spec_for_feature(team, product, "my-feature",
        requirements: %{
          "my-feature.COMP.1" => %{"requirement" => "Req 1"}
        },
        branch: branch,
        repo_uri: branch.repo_uri
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      expected_slug = Implementations.implementation_slug(impl)

      # feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format with dash separator
      assert expected_slug =~ ~r/^[a-z0-9-]+-[0-9a-f]{32}$/
      assert has_element?(view, "a[href='/t/#{team.name}/i/#{expected_slug}/f/my-feature']")
    end
  end

  describe "seeded data navigation regression" do
    setup :register_and_log_in_user

    # Regression test: API feature card links must lead to working feature-impl pages
    # Bug was: seed data inconsistency caused "Feature not found for this implementation" flash
    test "api feature card navigates to working feature-impl page", %{conn: conn, user: user} do
      # Run seeds first to create the mapperoni team and all seeded data
      Acai.Seeds.run(silent: true)

      # Get the mapperoni team (created by seeds)
      team = Acai.Repo.get_by!(Acai.Teams.Team, name: "mapperoni")
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      api_product = Acai.Repo.get_by!(Acai.Products.Product, team_id: team.id, name: "api")

      impl =
        Acai.Repo.get_by!(Acai.Implementations.Implementation,
          product_id: api_product.id,
          name: "Production"
        )

      slug = Acai.Implementations.implementation_slug(impl)

      # Navigate to API core feature page
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/core")

      # The card should have a link to the core feature-impl page for Production
      assert has_element?(view, "a[href='/t/#{team.name}/i/#{slug}/f/core']")

      # Actually navigate to the feature-impl page (regression: verify it mounts without error flash)
      {:ok, _impl_view, html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/core")

      # Should not show the "Feature not found for this implementation" flash
      refute html =~ "Feature not found for this implementation"

      # Should show the feature name
      assert html =~ "core"
    end

    test "api staging feature card navigates to working inherited feature-impl page", %{
      conn: conn,
      user: user
    } do
      # Run seeds first to create the mapperoni team and all seeded data
      Acai.Seeds.run(silent: true)

      # Get the mapperoni team (created by seeds)
      team = Acai.Repo.get_by!(Acai.Teams.Team, name: "mapperoni")
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      api_product = Acai.Repo.get_by!(Acai.Products.Product, team_id: team.id, name: "api")

      impl =
        Acai.Repo.get_by!(Acai.Implementations.Implementation,
          product_id: api_product.id,
          name: "Staging"
        )

      slug = Acai.Implementations.implementation_slug(impl)

      # Navigate to API mcp feature page
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/mcp")

      # The card should have a link to the mcp feature-impl page for Staging
      assert has_element?(view, "a[href='/t/#{team.name}/i/#{slug}/f/mcp']")

      # Actually navigate to the feature-impl page (regression: verify inherited spec resolution works)
      {:ok, _impl_view, html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/mcp")

      # Should not show the "Feature not found for this implementation" flash
      refute html =~ "Feature not found for this implementation"

      # Should show the feature name
      assert html =~ "mcp"
    end

    test "site feature card continues to work (shared branch product scoping)", %{
      conn: conn,
      user: user
    } do
      # Run seeds first to create the mapperoni team and all seeded data
      Acai.Seeds.run(silent: true)

      # Get the mapperoni team (created by seeds)
      team = Acai.Repo.get_by!(Acai.Teams.Team, name: "mapperoni")
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      site_product = Acai.Repo.get_by!(Acai.Products.Product, team_id: team.id, name: "site")

      impl =
        Acai.Repo.get_by!(Acai.Implementations.Implementation,
          product_id: site_product.id,
          name: "Production"
        )

      slug = Acai.Implementations.implementation_slug(impl)

      # Navigate to site map-editor feature page
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/map-editor")

      # The card should have a link to the map-editor feature-impl page
      assert has_element?(view, "a[href='/t/#{team.name}/i/#{slug}/f/map-editor']")

      # Actually navigate to the feature-impl page
      {:ok, _impl_view, html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/map-editor")

      # Should not show the "Feature not found for this implementation" flash
      refute html =~ "Feature not found for this implementation"

      # Should show the feature name
      assert html =~ "map-editor"
    end
  end

  describe "implementation card" do
    setup :register_and_log_in_user

    # feature-view.MAIN.1
    test "renders feature description when present", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      create_spec_for_feature(team, product, "my-feature",
        description: "This is a test feature description"
      )

      create_implementation_for_product(product, name: "Production")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "p", "This is a test feature description")
    end

    # feature-view.MAIN.1
    test "does not render description element when nil", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      spec = create_spec_for_feature(team, product, "my-feature", description: nil)

      # Update spec to ensure description is nil
      Acai.Specs.update_spec(spec, %{feature_description: nil})

      create_implementation_for_product(product, name: "Production")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      # Should still render the page without error
      assert has_element?(view, "button", "my-feature")
    end

    # feature-view.MAIN.3
    test "shows implementation name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create a shared branch first
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo", branch_name: "main"})

      # Create implementation
      impl = create_implementation_for_product(product, name: "Production")

      # Track the shared branch
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on the same branch so implementation can resolve it
      create_spec_for_feature(team, product, "my-feature",
        requirements: %{
          "my-feature.COMP.1" => %{"requirement" => "Req 1"}
        },
        branch: branch,
        repo_uri: branch.repo_uri
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "Production")
    end

    # feature-view.MAIN.3
    test "shows product name on each card", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create a shared branch first
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo", branch_name: "main"})

      # Create implementation
      impl = create_implementation_for_product(product, name: "Production")

      # Track the shared branch
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on the same branch so implementation can resolve it
      create_spec_for_feature(team, product, "my-feature",
        requirements: %{
          "my-feature.COMP.1" => %{"requirement" => "Req 1"}
        },
        branch: branch,
        repo_uri: branch.repo_uri
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "Production")
    end

    # feature-view.MAIN.3
    test "shows requirement count on implementation cards", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create implementation first
      impl = create_implementation_for_product(product)

      # Create tracked branch
      tracked = tracked_branch_fixture(impl, repo_uri: "github.com/org/repo", branch_name: "main")
      branch = Acai.Repo.preload(tracked, :branch).branch

      # Create spec with 4 requirements on the same branch
      requirements = %{
        "my-feature.COMP.1" => %{
          "requirement" => "Req 1",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "my-feature.COMP.2" => %{
          "requirement" => "Req 2",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "my-feature.COMP.3" => %{
          "requirement" => "Req 3",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "my-feature.COMP.4" => %{
          "requirement" => "Req 4",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      spec =
        create_spec_for_feature(team, product, "my-feature",
          requirements: requirements,
          branch: branch,
          repo_uri: branch.repo_uri
        )

      # Create spec_impl_state with mixed statuses
      states = %{
        "my-feature.COMP.1" => %{
          "status" => "completed",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "my-feature.COMP.2" => %{
          "status" => "completed",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "my-feature.COMP.3" => %{
          "status" => "assigned",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
        # COMP.4 has no status
      }

      create_spec_impl_state(spec, impl, states: states)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Should show requirement count
      assert has_element?(view, "#implementations-grid", "4 requirements")
    end

    # feature-view.MAIN.3
    test "shows segmented progress bar with status segments", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create implementation first
      impl = create_implementation_for_product(product)

      # Create tracked branch
      tracked = tracked_branch_fixture(impl, repo_uri: "github.com/org/repo", branch_name: "main")
      branch = Acai.Repo.preload(tracked, :branch).branch

      requirements = %{
        "my-feature.COMP.1" => %{
          "requirement" => "Req 1",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "my-feature.COMP.2" => %{
          "requirement" => "Req 2",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      spec =
        create_spec_for_feature(team, product, "my-feature",
          requirements: requirements,
          branch: branch,
          repo_uri: branch.repo_uri
        )

      # One completed, one with no status
      states = %{
        "my-feature.COMP.1" => %{
          "status" => "completed",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      create_spec_impl_state(spec, impl, states: states)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Should show implementation card with progress bar
      assert has_element?(view, "#implementations-grid", impl.name)
    end

    # feature-view.MAIN.3
    test "shows accepted status in progress bar", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create implementation first
      impl = create_implementation_for_product(product)

      # Create tracked branch
      tracked = tracked_branch_fixture(impl, repo_uri: "github.com/org/repo", branch_name: "main")
      branch = Acai.Repo.preload(tracked, :branch).branch

      requirements = %{
        "my-feature.COMP.1" => %{
          "requirement" => "Req 1",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      spec =
        create_spec_for_feature(team, product, "my-feature",
          requirements: requirements,
          branch: branch,
          repo_uri: branch.repo_uri
        )

      create_spec_impl_state(spec, impl, status: "accepted")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Should show implementation card with progress bar
      assert has_element?(view, "#implementations-grid", impl.name)
    end
  end

  describe "routing" do
    setup :register_and_log_in_user

    # feature-view.ROUTING.1
    test "case-insensitive feature_name matching", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "MyFeature")

      # Test various case combinations
      for feature_name <- ["MyFeature", "myfeature", "MYFEATURE", "Myfeature"] do
        {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/#{feature_name}")
        # Feature name is in the dropdown button
        assert has_element?(view, "button", "MyFeature")
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
      product = create_product(team, "TestProduct")

      # Create a shared branch first
      branch = branch_fixture(team, %{repo_uri: "github.com/org/repo", branch_name: "main"})

      # Create implementation
      impl = create_implementation_for_product(product, name: "MyImpl")

      # Track the shared branch
      tracked_branch_fixture(impl, branch: branch, repo_uri: branch.repo_uri)

      # Create spec on the same branch so implementation can resolve it
      create_spec_for_feature(team, product, "my-feature",
        requirements: %{
          "my-feature.COMP.1" => %{"requirement" => "Req 1"}
        },
        branch: branch,
        repo_uri: branch.repo_uri
      )

      # Create another team with a different user
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      other_product = create_product(other_team, "TestProduct")

      # Create separate branch for other team
      other_branch =
        branch_fixture(other_team, %{repo_uri: "github.com/other/repo", branch_name: "main"})

      # Create implementation and spec for other team on different branch
      other_impl = create_implementation_for_product(other_product, name: "OtherImpl")
      tracked_branch_fixture(other_impl, branch: other_branch, repo_uri: other_branch.repo_uri)

      create_spec_for_feature(other_team, other_product, "my-feature",
        requirements: %{
          "my-feature.COMP.1" => %{"requirement" => "Req 1"}
        },
        branch: other_branch,
        repo_uri: other_branch.repo_uri
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      # Should only show implementations from the current team
      assert has_element?(view, "#implementations-grid", "MyImpl")
      refute has_element?(view, "#implementations-grid", "OtherImpl")
    end

    test "only shows active implementations", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create implementations first
      active_impl =
        create_implementation_for_product(product, name: "ActiveImpl", is_active: true)

      create_implementation_for_product(product, name: "InactiveImpl", is_active: false)

      # Create tracked branch for active implementation only
      tracked =
        tracked_branch_fixture(active_impl, repo_uri: "github.com/org/repo", branch_name: "main")

      branch = Acai.Repo.preload(tracked, :branch).branch

      # Create spec on the same branch so active implementation can resolve it
      create_spec_for_feature(team, product, "my-feature",
        requirements: %{
          "my-feature.COMP.1" => %{"requirement" => "Req 1"}
        },
        branch: branch,
        repo_uri: branch.repo_uri
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "ActiveImpl")
      refute has_element?(view, "#implementations-grid", "InactiveImpl")
    end
  end

  describe "specs context functions" do
    setup :register_and_log_in_user

    test "get_specs_by_feature_name returns correct feature and specs", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      spec1 = create_spec_for_feature(team, product, "MyFeature", version: "1.0.0")
      spec2 = create_spec_for_feature(team, product, "MyFeature", version: "2.0.0")

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
      product = create_product(team, "TestProduct")
      spec1 = create_spec_for_feature(team, product, "feature-1")

      # Create another product with a spec
      product2 = create_product(team, "TestProduct2")
      spec2 = create_spec_for_feature(team, product2, "feature-2")

      impl1 = create_implementation_for_product(product, is_active: true)
      impl2 = create_implementation_for_product(product2, is_active: true)
      create_implementation_for_product(product, is_active: false)

      impls = Implementations.list_active_implementations_for_specs([spec1, spec2])
      assert length(impls) == 2
      assert Enum.any?(impls, &(&1.id == impl1.id))
      assert Enum.any?(impls, &(&1.id == impl2.id))
    end

    test "count_tracked_branches returns correct count", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      impl = create_implementation_for_product(product)

      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo1")
      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo2")
      tracked_branch_fixture(impl, repo_uri: "github.com/org/repo3")

      count = Implementations.count_tracked_branches(impl)
      assert count == 3
    end

    test "batch_get_spec_impl_state_counts returns correct counts", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      requirements = %{
        "feature-1.COMP.1" => %{
          "requirement" => "Req 1",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "feature-1.COMP.2" => %{
          "requirement" => "Req 2",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "feature-1.COMP.3" => %{
          "requirement" => "Req 3",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      spec = create_spec_for_feature(team, product, "feature-1", requirements: requirements)
      impl = create_implementation_for_product(product)

      # Create spec_impl_state with 1 completed, 1 in_progress, 1 pending
      states = %{
        "feature-1.COMP.1" => %{
          "status" => "completed",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "feature-1.COMP.2" => %{
          "status" => "in_progress",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        },
        "feature-1.COMP.3" => %{
          "status" => "pending",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
      }

      create_spec_impl_state(spec, impl, states: states)

      counts = Implementations.batch_get_spec_impl_state_counts([impl])
      impl_counts = Map.get(counts, impl.id, %{})

      assert impl_counts["completed"] == 1
      assert impl_counts["in_progress"] == 1
      assert impl_counts["pending"] == 1
    end
  end

  describe "feature-view filtering and inheritance" do
    setup :register_and_log_in_user

    # feature-view.MAIN.2: Implementations without the feature should not render cards
    test "does not render cards for implementations without the feature", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create tracked branch and spec for feature-1 on the SAME branch
      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "feature-1",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{
          "feature-1.COMP.1" => %{
            "requirement" => "Req 1",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create implementation WITH the feature (tracked branch)
      impl_with =
        create_implementation_for_product(product, name: "WithFeature", is_active: true)

      tracked_branch_fixture(impl_with, branch: branch, repo_uri: branch.repo_uri)

      # Create implementation WITHOUT the feature (no tracked branch)
      create_implementation_for_product(product, name: "WithoutFeature", is_active: true)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/feature-1")

      # Should only show implementation with the feature
      assert has_element?(view, "#implementations-grid", "WithFeature")
      refute has_element?(view, "#implementations-grid", "WithoutFeature")
    end

    # feature-view.MAIN.2: Inherited implementations should render cards
    test "renders cards for inherited implementations", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create tracked branch and spec on the SAME branch
      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "inherited-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{
          "inherited-feature.COMP.1" => %{
            "requirement" => "Req 1",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create parent implementation with tracked branch
      parent =
        create_implementation_for_product(product, name: "ParentImpl", is_active: true)

      tracked_branch_fixture(parent, branch: branch, repo_uri: branch.repo_uri)

      # Create child implementation that inherits (no tracked branch, has parent)
      _child =
        create_implementation_for_product(product,
          name: "ChildImpl",
          is_active: true,
          parent_implementation_id: parent.id
        )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/inherited-feature")

      # Should show both parent and child
      assert has_element?(view, "#implementations-grid", "ParentImpl")
      assert has_element?(view, "#implementations-grid", "ChildImpl")
    end

    # feature-view.ENG.2: Inherited implementations show inherited progress
    test "inherited implementations show inherited progress", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create tracked branch and spec
      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "progress-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{
          "progress-feature.COMP.1" => %{
            "requirement" => "Req 1",
            "is_deprecated" => false,
            "replaced_by" => []
          },
          "progress-feature.COMP.2" => %{
            "requirement" => "Req 2",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      # Create parent implementation with tracked branch
      parent =
        create_implementation_for_product(product, name: "ParentProgress", is_active: true)

      tracked_branch_fixture(parent, branch: branch, repo_uri: branch.repo_uri)

      # Create child implementation that inherits
      _child =
        create_implementation_for_product(product,
          name: "ChildProgress",
          is_active: true,
          parent_implementation_id: parent.id
        )

      # Create state for parent only (1 completed, 1 pending = 50%)
      # Child should inherit this progress
      Acai.Specs.create_feature_impl_state("progress-feature", parent, %{
        states: %{
          "progress-feature.COMP.1" => %{"status" => "completed"},
          "progress-feature.COMP.2" => %{"status" => nil}
        }
      })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/progress-feature")

      # Should show both implementations
      assert has_element?(view, "#implementations-grid", "ParentProgress")
      assert has_element?(view, "#implementations-grid", "ChildProgress")

      # Both should show "2 requirements" (child inherits the spec requirement count)
      assert has_element?(view, "#implementations-grid", "2 requirements")
    end
  end

  describe "hierarchy display" do
    setup :register_and_log_in_user

    # feature-view.HIERARCHY.1, feature-view.HIERARCHY.2
    test "renders cards in depth-first hierarchy order", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create shared branch for specs
      branch = branch_fixture(team)

      # Create a spec for the feature
      spec_fixture(product, %{
        feature_name: "hierarchy-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{"hierarchy-feature.COMP.1" => %{"requirement" => "Req 1"}}
      })

      # Create tree: Parent -> Child1 -> GrandChild, Parent -> Child2
      parent =
        create_implementation_for_product(product, name: "Parent-Root", is_active: true)

      tracked_branch_fixture(parent, branch: branch, repo_uri: branch.repo_uri)

      child1 =
        create_implementation_for_product(product,
          name: "Child-1",
          is_active: true,
          parent_implementation_id: parent.id
        )

      tracked_branch_fixture(child1, branch: branch, repo_uri: branch.repo_uri)

      grandchild =
        create_implementation_for_product(product,
          name: "GrandChild",
          is_active: true,
          parent_implementation_id: child1.id
        )

      tracked_branch_fixture(grandchild, branch: branch, repo_uri: branch.repo_uri)

      child2 =
        create_implementation_for_product(product,
          name: "Child-2",
          is_active: true,
          parent_implementation_id: parent.id
        )

      tracked_branch_fixture(child2, branch: branch, repo_uri: branch.repo_uri)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/hierarchy-feature")

      # feature-view.HIERARCHY.1, feature-view.HIERARCHY.2: Verify depth-first order
      # Expected: Parent-Root, Child-1, GrandChild, Child-2
      # Use selector-based assertions via element() to find cards in DOM order

      # Get all implementation cards by their stream DOM ID pattern
      # The cards have IDs like "implementations-impl-{uuid}" and data-depth attributes
      html = render(view)

      # Extract card order using render() output with string matching
      # Each card link contains data-depth and the implementation name in an h3
      card_pattern = ~r/<div[^>]*data-depth="(\d+)"[^>]*>.*?<h3[^>]*>([^<]+)<\/h3>/s
      cards = Regex.scan(card_pattern, html)

      assert length(cards) == 4,
             "Expected 4 cards but found #{length(cards)}"

      # Verify order: Parent-Root (depth 1), Child-1 (depth 2), GrandChild (depth 3), Child-2 (depth 2)
      # Parent-Root at depth 1
      assert Enum.at(cards, 0) |> Enum.at(1) == "1"
      assert Enum.at(cards, 0) |> Enum.at(2) =~ "Parent-Root"

      # Child-1 at depth 2
      assert Enum.at(cards, 1) |> Enum.at(1) == "2"
      assert Enum.at(cards, 1) |> Enum.at(2) =~ "Child-1"

      # GrandChild at depth 3
      assert Enum.at(cards, 2) |> Enum.at(1) == "3"
      assert Enum.at(cards, 2) |> Enum.at(2) =~ "GrandChild"

      # Child-2 at depth 2
      assert Enum.at(cards, 3) |> Enum.at(1) == "2"
      assert Enum.at(cards, 3) |> Enum.at(2) =~ "Child-2"
    end

    # feature-view.HIERARCHY.3: Visual depth indicators for levels 1-4
    test "renders distinct depth indicators through level 4", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create shared branch for specs
      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "depth-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{"depth-feature.COMP.1" => %{"requirement" => "Req 1"}}
      })

      # Create 4-level chain: L1 -> L2 -> L3 -> L4
      level1 =
        create_implementation_for_product(product, name: "Level-1", is_active: true)

      tracked_branch_fixture(level1, branch: branch, repo_uri: branch.repo_uri)

      level2 =
        create_implementation_for_product(product,
          name: "Level-2",
          is_active: true,
          parent_implementation_id: level1.id
        )

      tracked_branch_fixture(level2, branch: branch, repo_uri: branch.repo_uri)

      level3 =
        create_implementation_for_product(product,
          name: "Level-3",
          is_active: true,
          parent_implementation_id: level2.id
        )

      tracked_branch_fixture(level3, branch: branch, repo_uri: branch.repo_uri)

      level4 =
        create_implementation_for_product(product,
          name: "Level-4",
          is_active: true,
          parent_implementation_id: level3.id
        )

      tracked_branch_fixture(level4, branch: branch, repo_uri: branch.repo_uri)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/depth-feature")

      # feature-view.HIERARCHY.3: Verify each card has correct data-depth
      # Use has_element? to verify data-depth attributes tied to specific implementation names
      assert has_element?(view, "[data-depth='1']", "Level-1")
      refute has_element?(view, "[data-depth='1']", "Level-2")
      refute has_element?(view, "[data-depth='1']", "Level-3")
      refute has_element?(view, "[data-depth='1']", "Level-4")

      assert has_element?(view, "[data-depth='2']", "Level-2")
      refute has_element?(view, "[data-depth='2']", "Level-1")
      refute has_element?(view, "[data-depth='2']", "Level-3")
      refute has_element?(view, "[data-depth='2']", "Level-4")

      assert has_element?(view, "[data-depth='3']", "Level-3")
      refute has_element?(view, "[data-depth='3']", "Level-1")
      refute has_element?(view, "[data-depth='3']", "Level-2")
      refute has_element?(view, "[data-depth='3']", "Level-4")

      assert has_element?(view, "[data-depth='4']", "Level-4")
      refute has_element?(view, "[data-depth='4']", "Level-1")
      refute has_element?(view, "[data-depth='4']", "Level-2")
      refute has_element?(view, "[data-depth='4']", "Level-3")

      # Verify left rail depth indicators exist with different colors
      assert has_element?(view, "[data-depth='1'] .bg-primary")
      assert has_element?(view, "[data-depth='2'] .bg-secondary")
      assert has_element?(view, "[data-depth='3'] .bg-accent")
      assert has_element?(view, "[data-depth='4'] .bg-neutral")
    end

    # feature-view.HIERARCHY.4: Level 5+ flattened to depth 4
    test "flattens implementations beyond depth 4 to depth 4", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create shared branch for specs
      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "deep-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{"deep-feature.COMP.1" => %{"requirement" => "Req 1"}}
      })

      # Create 5-level chain: L1 -> L2 -> L3 -> L4 -> L5
      level1 =
        create_implementation_for_product(product, name: "Level-1", is_active: true)

      tracked_branch_fixture(level1, branch: branch, repo_uri: branch.repo_uri)

      level2 =
        create_implementation_for_product(product,
          name: "Level-2",
          is_active: true,
          parent_implementation_id: level1.id
        )

      tracked_branch_fixture(level2, branch: branch, repo_uri: branch.repo_uri)

      level3 =
        create_implementation_for_product(product,
          name: "Level-3",
          is_active: true,
          parent_implementation_id: level2.id
        )

      tracked_branch_fixture(level3, branch: branch, repo_uri: branch.repo_uri)

      level4 =
        create_implementation_for_product(product,
          name: "Level-4",
          is_active: true,
          parent_implementation_id: level3.id
        )

      tracked_branch_fixture(level4, branch: branch, repo_uri: branch.repo_uri)

      level5 =
        create_implementation_for_product(product,
          name: "Level-5",
          is_active: true,
          parent_implementation_id: level4.id
        )

      tracked_branch_fixture(level5, branch: branch, repo_uri: branch.repo_uri)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/deep-feature")

      # feature-view.HIERARCHY.3, feature-view.HIERARCHY.4: Verify depth attributes
      # Levels 1-4 have their actual depth
      assert has_element?(view, "[data-depth='1']", "Level-1")
      assert has_element?(view, "[data-depth='2']", "Level-2")
      assert has_element?(view, "[data-depth='3']", "Level-3")
      assert has_element?(view, "[data-depth='4']", "Level-4")

      # feature-view.HIERARCHY.4: Level-5 MUST have data-depth="4" (flattened, not "5")
      # Verify Level-5 specifically has data-depth="4" (not "5")
      assert has_element?(view, "[data-depth='4']", "Level-5")
      refute has_element?(view, "[data-depth='5']", "Level-5")

      # Verify there are exactly 2 cards at depth 4 (Level-4 and Level-5)
      html = render(view)
      depth_4_count = Regex.scan(~r/data-depth="4"/, html) |> length()

      assert depth_4_count == 2,
             "Expected exactly 2 cards with data-depth=4 (Level-4 and Level-5), found #{depth_4_count}"

      # feature-view.HIERARCHY.1, feature-view.HIERARCHY.2: Verify depth-first order still holds
      # Level-5 should still appear after Level-4 (depth-first order preserved)
      card_pattern = ~r/<div[^>]*data-depth="(\d+)"[^>]*>.*?<h3[^>]*>([^<]+)<\/h3>/s
      cards = Regex.scan(card_pattern, html)

      level4_idx = Enum.find_index(cards, fn [_, _, name] -> name =~ "Level-4" end)
      level5_idx = Enum.find_index(cards, fn [_, _, name] -> name =~ "Level-5" end)

      assert level4_idx != nil, "Level-4 not found in cards: #{inspect(cards)}"
      assert level5_idx != nil, "Level-5 not found in cards: #{inspect(cards)}"
      assert level4_idx < level5_idx
    end

    test "exposes stable depth indication via data-depth attribute", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create shared branch for specs
      branch = branch_fixture(team)

      spec_fixture(product, %{
        feature_name: "indicator-feature",
        branch: branch,
        repo_uri: branch.repo_uri,
        requirements: %{"indicator-feature.COMP.1" => %{"requirement" => "Req 1"}}
      })

      # Create parent and child
      parent =
        create_implementation_for_product(product, name: "Parent", is_active: true)

      tracked_branch_fixture(parent, branch: branch, repo_uri: branch.repo_uri)

      child =
        create_implementation_for_product(product,
          name: "Child",
          is_active: true,
          parent_implementation_id: parent.id
        )

      tracked_branch_fixture(child, branch: branch, repo_uri: branch.repo_uri)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/indicator-feature")

      # Use has_element? to verify the data-depth attribute on each specific card
      assert has_element?(view, "[data-depth='1']", "Parent")
      refute has_element?(view, "[data-depth='1']", "Child")

      assert has_element?(view, "[data-depth='2']", "Child")
      refute has_element?(view, "[data-depth='2']", "Parent")
    end

    # feature-view.HIERARCHY.1: Cards with missing parents treated as roots
    # This tests the scenario where a child's parent is NOT in the filtered card set
    # (parent doesn't have the feature, but child does)
    test "treats cards with missing parents as roots", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create TWO separate branches for this test
      # Parent will be on branch_without_feature (doesn't have the feature)
      # Child will be on branch_with_feature (has the feature)
      _branch_without_feature = branch_fixture(team, %{branch_name: "parent-branch"})
      branch_with_feature = branch_fixture(team, %{branch_name: "child-branch"})

      # Create spec ONLY on branch_with_feature
      spec_fixture(product, %{
        feature_name: "orphan-feature",
        branch: branch_with_feature,
        repo_uri: branch_with_feature.repo_uri,
        requirements: %{"orphan-feature.COMP.1" => %{"requirement" => "Req 1"}}
      })

      # Create parent implementation (NO tracked branch = parent doesn't have the feature)
      parent =
        create_implementation_for_product(product, name: "Parent-Orphaned", is_active: true)

      # Parent is NOT tracked on any branch with this feature, so it won't appear on the page

      # Create child that references parent (child DOES have the feature via tracked branch)
      child =
        create_implementation_for_product(product,
          name: "Child-With-Feature",
          is_active: true,
          parent_implementation_id: parent.id
        )

      # Child IS tracked on the branch with the feature, so it WILL appear
      tracked_branch_fixture(child,
        branch: branch_with_feature,
        repo_uri: branch_with_feature.repo_uri
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/orphan-feature")

      # feature-view.HIERARCHY.1: Child should be rendered even though its parent is not on the page
      assert has_element?(view, "#implementations-grid", "Child-With-Feature")

      # Parent should NOT be rendered (it doesn't have the feature)
      refute has_element?(view, "#implementations-grid", "Parent-Orphaned")

      # feature-view.HIERARCHY.1: Child should be treated as a root (data-depth="1")
      # because its parent is not in the filtered card set
      assert has_element?(view, "[data-depth='1']", "Child-With-Feature")
      refute has_element?(view, "[data-depth='2']", "Child-With-Feature")
    end
  end

  describe "feature navigation" do
    setup :register_and_log_in_user

    # feature-view.ENG.1: Stream reset on feature navigation removes stale cards
    test "feature switch removes stale implementation cards", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create two different features with different implementations
      # Each feature is on a different branch, each implementation tracks only one branch

      # Feature 1: Only Impl-A has this feature
      branch1 = branch_fixture(team, %{repo_uri: "github.com/org/repo1"})

      spec_fixture(product, %{
        feature_name: "feature-a",
        branch: branch1,
        repo_uri: branch1.repo_uri,
        requirements: %{
          "feature-a.COMP.1" => %{
            "requirement" => "Req A1",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      impl_a =
        create_implementation_for_product(product, name: "Impl-A", is_active: true)

      tracked_branch_fixture(impl_a, branch: branch1, repo_uri: branch1.repo_uri)

      # Feature 2: Only Impl-B has this feature
      branch2 = branch_fixture(team, %{repo_uri: "github.com/org/repo2"})

      spec_fixture(product, %{
        feature_name: "feature-b",
        branch: branch2,
        repo_uri: branch2.repo_uri,
        requirements: %{
          "feature-b.COMP.1" => %{
            "requirement" => "Req B1",
            "is_deprecated" => false,
            "replaced_by" => []
          }
        }
      })

      impl_b =
        create_implementation_for_product(product, name: "Impl-B", is_active: true)

      tracked_branch_fixture(impl_b, branch: branch2, repo_uri: branch2.repo_uri)

      # Start on feature-a page
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/feature-a")

      # Should show Impl-A card
      assert has_element?(view, "#implementations-grid", "Impl-A")
      refute has_element?(view, "#implementations-grid", "Impl-B")

      # Navigate to feature-b via patch navigation
      # This tests that the stream is reset properly when switching features
      html = render_patch(view, ~p"/t/#{team.name}/f/feature-b")

      # After the patch, feature-b should be shown and Impl-B should appear
      # Verify we're on the right page (feature-b should be in the HTML)
      assert html =~ "feature-b"

      # Impl-A should no longer be shown (stream reset)
      refute has_element?(view, "#implementations-grid", "Impl-A")

      # Impl-B should now be shown
      assert has_element?(view, "#implementations-grid", "Impl-B")
    end
  end
end
