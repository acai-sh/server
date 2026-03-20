defmodule AcaiWeb.ProductLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.AccountsFixtures
  import Acai.DataModelFixtures

  alias Acai.Products
  alias Acai.Implementations

  # Helper to set up a team with an owner (the logged-in user)
  defp create_team_with_owner(user) do
    team = team_fixture()
    role = user_team_role_fixture(team, user, %{title: "owner"})
    {team, role}
  end

  # data-model.PRODUCTS: Create product as first-class entity
  defp create_product(team, name, opts \\ []) do
    product_fixture(team, %{
      name: name,
      description: Keyword.get(opts, :description, "Description for #{name}"),
      is_active: true
    })
  end

  # data-model.SPECS: Create spec for a product
  defp create_spec_for_product(_team, product, feature_name, opts \\ []) do
    unique_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    # Create requirements map for completion tracking
    requirements =
      Keyword.get(opts, :requirements, %{
        "test.1" => %{"description" => "Requirement 1"},
        "test.2" => %{"description" => "Requirement 2"},
        "test.3" => %{"description" => "Requirement 3"},
        "test.4" => %{"description" => "Requirement 4"}
      })

    spec_fixture(product, %{
      feature_name: feature_name,
      feature_description: Keyword.get(opts, :description, "Description for #{feature_name}"),
      feature_version: Keyword.get(opts, :feature_version, "1.0.0"),
      path: "features/#{feature_name}-#{unique_suffix}/feature.yaml",
      repo_uri: "github.com/test/repo-#{unique_suffix}",
      requirements: requirements
    })
  end

  # data-model.IMPLS: Create implementation for a product (not a spec)
  defp create_implementation_for_product(product, opts) do
    attrs = %{
      name: Keyword.get(opts, :name, "Impl-#{System.unique_integer([:positive])}"),
      is_active: Keyword.get(opts, :is_active, true)
    }

    # Add parent_implementation_id if provided
    attrs =
      if Keyword.has_key?(opts, :parent_implementation_id) do
        Map.put(attrs, :parent_implementation_id, Keyword.get(opts, :parent_implementation_id))
      else
        attrs
      end

    implementation_fixture(product, attrs)
  end

  # Create spec_impl_state with completion data
  # Note: states keys must match spec.requirements keys for completion tracking
  defp create_spec_impl_state(spec, implementation, states) do
    Acai.Specs.create_spec_impl_state(spec, implementation, %{states: states})
  end

  # Create tracked branch linking implementation to a spec's branch
  # This makes the feature "available" to the implementation
  defp track_spec_branch(implementation, spec) do
    branch = Acai.Repo.preload(spec, :branch).branch
    tracked_branch_fixture(implementation, branch: branch, repo_uri: branch.repo_uri)
  end

  describe "unauthenticated access" do
    test "redirects to log-in", %{conn: conn} do
      team = team_fixture()
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/t/#{team.name}/p/some-product")
      assert path == ~p"/users/log-in"
    end
  end

  describe "mount" do
    setup :register_and_log_in_user

    # product-view.ROUTING.1
    test "renders the product name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_product(team, product, "feature-1")
      create_implementation_for_product(product, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "span", "MyProduct")
    end

    # product-view.ROUTING.1
    test "renders product name with case-insensitive matching", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_product(team, product, "feature-1")
      create_implementation_for_product(product, name: "Impl-1")

      # Access with lowercase URL
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/myproduct")
      # Should display the actual product name from database
      assert has_element?(view, "span", "MyProduct")
    end

    # product-view.ROUTING.2
    test "redirects to team page when product not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)

      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/t/#{team.name}/p/NonExistentProduct")

      assert redirect_to == ~p"/t/#{team.name}"
    end

    # product-view.ROUTING.2
    test "shows flash message when product not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)

      assert {:error, {:live_redirect, %{flash: flash}}} =
               live(conn, ~p"/t/#{team.name}/p/NonExistentProduct")

      assert flash["error"] == "Product not found"
    end
  end

  describe "matrix view" do
    setup :register_and_log_in_user

    # product-view.MATRIX.1
    test "renders matrix with implementation columns", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_product(team, product, "feature-1")
      create_implementation_for_product(product, name: "Impl-1")
      create_implementation_for_product(product, name: "Impl-2")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Should have table with implementation headers
      assert has_element?(view, "table")
      assert has_element?(view, "th", "Impl-1")
      assert has_element?(view, "th", "Impl-2")
    end

    # product-view.MATRIX.1
    test "only shows active implementations as columns", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_product(team, product, "feature-1")
      create_implementation_for_product(product, name: "Active-Impl", is_active: true)
      create_implementation_for_product(product, name: "Inactive-Impl", is_active: false)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      assert has_element?(view, "th", "Active-Impl")
      refute has_element?(view, "th", "Inactive-Impl")
    end

    # product-view.MATRIX.2
    test "renders matrix with feature rows", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_implementation_for_product(product, name: "Impl-1")
      create_spec_for_product(team, product, "feature-alpha")
      create_spec_for_product(team, product, "feature-beta")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      assert has_element?(view, "td", "feature-alpha")
      assert has_element?(view, "td", "feature-beta")
    end

    # product-view.MATRIX.3
    test "cells show completion percentage", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      # Use consistent ACID keys for requirements and states
      spec =
        create_spec_for_product(team, product, "my-feature",
          requirements: %{
            "my-feature.COMP.1" => %{"description" => "Req 1"},
            "my-feature.COMP.2" => %{"description" => "Req 2"},
            "my-feature.COMP.3" => %{"description" => "Req 3"},
            "my-feature.COMP.4" => %{"description" => "Req 4"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # Link implementation to spec's branch so feature is available
      track_spec_branch(impl, spec)

      # Set 2 out of 4 requirements as completed (50%)
      # Keys must match the requirement ACIDs exactly
      create_spec_impl_state(spec, impl, %{
        "my-feature.COMP.1" => %{"status" => "completed"},
        "my-feature.COMP.2" => %{"status" => "completed"},
        "my-feature.COMP.3" => %{"status" => "pending"},
        "my-feature.COMP.4" => %{"status" => "pending"}
      })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Cell should show 50%
      assert has_element?(view, "table td", "50%")
      assert has_element?(view, "table td", "2/4")
    end

    # product-view.MATRIX.3
    test "cells show 0% when no spec_impl_state exists", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      spec =
        create_spec_for_product(team, product, "my-feature",
          requirements: %{
            "my-feature.COMP.1" => %{"description" => "Req 1"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # Link implementation to spec's branch so feature is available
      track_spec_branch(impl, spec)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      assert has_element?(view, "table td", "0%")
    end

    # product-view.MATRIX.3
    test "cells show 100% when all requirements completed", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      spec =
        create_spec_for_product(team, product, "my-feature",
          requirements: %{
            "my-feature.COMP.1" => %{"description" => "Req 1"},
            "my-feature.COMP.2" => %{"description" => "Req 2"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # Link implementation to spec's branch so feature is available
      track_spec_branch(impl, spec)

      create_spec_impl_state(spec, impl, %{
        "my-feature.COMP.1" => %{"status" => "completed"},
        "my-feature.COMP.2" => %{"status" => "completed"}
      })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      assert has_element?(view, "table td", "100%")
    end

    # product-view.MATRIX.5
    test "clicking feature row navigates to feature view", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_product(team, product, "my-feature")
      create_implementation_for_product(product, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      assert has_element?(view, "a[href='/t/#{team.name}/f/my-feature']")
    end

    # product-view.MATRIX.7
    test "clicking cell navigates to feature-impl view", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      spec =
        create_spec_for_product(team, product, "my-feature",
          requirements: %{
            "my-feature.COMP.1" => %{"description" => "Req 1"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # Link implementation to spec's branch so feature is available and cell is clickable
      track_spec_branch(impl, spec)

      slug = Implementations.implementation_slug(impl)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Cell should link to feature-impl view
      assert has_element?(view, "a[href='/t/#{team.name}/i/#{slug}/f/my-feature']")
    end

    # product-view.MATRIX.6
    test "shows empty state when product has no features", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      # Create a product with no specs
      _product = create_product(team, "EmptyProduct")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/EmptyProduct")

      assert has_element?(view, "h3", "No features found")
      assert has_element?(view, "p", "This product doesn't have any feature specs yet")
    end

    # product-view.MATRIX.6
    test "shows empty state when product has no active implementations", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      # Create spec but no active implementations
      create_spec_for_product(team, product, "feature-1")
      create_implementation_for_product(product, name: "Inactive", is_active: false)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      assert has_element?(view, "h3", "No active implementations")
      assert has_element?(view, "p", "This product doesn't have any active implementations")
    end
  end

  describe "seeded data navigation regression" do
    setup :register_and_log_in_user

    # Regression test: API product matrix links must lead to working feature-impl pages
    # Bug was: seed data inconsistency caused "Feature not found for this implementation" flash
    test "api product matrix cell navigates to working feature-impl page", %{
      conn: conn,
      user: user
    } do
      # Run seeds first to create the mapperoni team and all seeded data
      Acai.Seeds.run(silent: true)

      # Get the mapperoni team (created by seeds)
      team = Acai.Repo.get_by!(Acai.Teams.Team, name: "mapperoni")
      _role = user_team_role_fixture(team, user, %{title: "owner"})

      # Run seeds to ensure data exists
      Acai.Seeds.run(silent: true)

      api_product = Acai.Repo.get_by!(Acai.Products.Product, team_id: team.id, name: "api")

      impl =
        Acai.Repo.get_by!(Acai.Implementations.Implementation,
          product_id: api_product.id,
          name: "Production"
        )

      slug = Acai.Implementations.implementation_slug(impl)

      # Navigate to API product page
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/api")

      # The matrix should have a link to the core feature-impl page
      assert has_element?(view, "a[href='/t/#{team.name}/i/#{slug}/f/core']")

      # Actually navigate to the feature-impl page (regression: verify it mounts without error flash)
      {:ok, _impl_view, html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/core")

      # Should not show the "Feature not found for this implementation" flash
      refute html =~ "Feature not found for this implementation"

      # Should show the feature name instead
      assert html =~ "core"
    end

    test "site product matrix cell continues to work (shared branch product scoping)", %{
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

      # Navigate to site product page
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/site")

      # The matrix should have a link to the map-editor feature-impl page
      assert has_element?(view, "a[href='/t/#{team.name}/i/#{slug}/f/map-editor']")

      # Actually navigate to the feature-impl page
      {:ok, _impl_view, html} = live(conn, ~p"/t/#{team.name}/i/#{slug}/f/map-editor")

      # Should not show the "Feature not found for this implementation" flash
      refute html =~ "Feature not found for this implementation"

      # Should show the feature name
      assert html =~ "map-editor"
    end
  end

  describe "page header" do
    setup :register_and_log_in_user

    test "renders product name in title", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_product(team, product, "feature-1")
      create_implementation_for_product(product, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      html = render(view)
      assert html =~ "Overview of the"
      assert html =~ "MyProduct"
    end

    test "renders breadcrumb with home link", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_product(team, product, "feature-1")
      create_implementation_for_product(product, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Should have breadcrumb with home icon
      assert has_element?(view, "nav a[href='/t/#{team.name}']")
      html = render(view)
      assert html =~ "Overview of the"
      assert html =~ "MyProduct"
    end
  end

  describe "color gradient" do
    setup :register_and_log_in_user

    # product-view.MATRIX.4
    test "0% completion shows default color", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      spec =
        create_spec_for_product(team, product, "my-feature",
          requirements: %{
            "my-feature.COMP.1" => %{"description" => "Req 1"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # Link implementation to spec's branch so feature is available
      track_spec_branch(impl, spec)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # 0% should have no special style (empty style attribute or default color)
      html = render(view)
      # The 0% cell should not have a green color style
      assert html =~ "0%"
    end

    # product-view.MATRIX.4
    test "50% completion shows default color", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      spec =
        create_spec_for_product(team, product, "my-feature",
          requirements: %{
            "my-feature.COMP.1" => %{"description" => "Req 1"},
            "my-feature.COMP.2" => %{"description" => "Req 2"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # Link implementation to spec's branch so feature is available
      track_spec_branch(impl, spec)

      # 1 of 2 completed = 50%
      create_spec_impl_state(spec, impl, %{
        "my-feature.COMP.1" => %{"status" => "completed"},
        "my-feature.COMP.2" => %{"status" => "pending"}
      })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # 50% should have default/less color
      html = render(view)
      assert html =~ "50%"
    end

    # product-view.MATRIX.4
    test "100% completion shows green highlight", %{conn: conn, user: king_user} do
      {team, _role} = create_team_with_owner(king_user)
      product = create_product(team, "MyProduct")

      spec =
        create_spec_for_product(team, product, "my-feature",
          requirements: %{
            "my-feature.COMP.1" => %{"description" => "Req 1"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # Link implementation to spec's branch so feature is available
      track_spec_branch(impl, spec)

      create_spec_impl_state(spec, impl, %{
        "my-feature.COMP.1" => %{"status" => "completed"}
      })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # 100% cell should have success background class
      # Check for the bg-success/3 class in the rendered HTML
      html = render(view)
      assert html =~ "bg-success/3"
      assert has_element?(view, "td", "100%")
    end
  end

  describe "multiple specs per feature" do
    setup :register_and_log_in_user

    test "aggregates completion across multiple specs for same feature", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      # Create two specs with the same feature_name but different versions
      spec1 =
        create_spec_for_product(team, product, "shared-feature",
          feature_version: "1.0.0",
          requirements: %{
            "shared-feature.COMP.1" => %{"description" => "Spec1 Req 1"},
            "shared-feature.COMP.2" => %{"description" => "Spec1 Req 2"}
          }
        )

      spec2 =
        create_spec_for_product(team, product, "shared-feature",
          feature_version: "2.0.0",
          requirements: %{
            "shared-feature.COMP.3" => %{"description" => "Spec2 Req 1"},
            "shared-feature.COMP.4" => %{"description" => "Spec2 Req 2"},
            "shared-feature.COMP.5" => %{"description" => "Spec2 Req 3"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # Link implementation to both specs' branches so feature is available
      track_spec_branch(impl, spec1)
      track_spec_branch(impl, spec2)

      # Complete 1/2 from spec1 and 2/3 from spec2 = 3/5 total = 60%
      create_spec_impl_state(spec1, impl, %{
        "shared-feature.COMP.1" => %{"status" => "completed"},
        "shared-feature.COMP.2" => %{"status" => "pending"}
      })

      create_spec_impl_state(spec2, impl, %{
        "shared-feature.COMP.3" => %{"status" => "completed"},
        "shared-feature.COMP.4" => %{"status" => "completed"},
        "shared-feature.COMP.5" => %{"status" => "pending"}
      })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Should show 60% (3/5)
      assert has_element?(view, "table td", "60%")
      assert has_element?(view, "table td", "3/5")
    end
  end

  describe "isolation" do
    setup :register_and_log_in_user

    test "only shows features for the correct team", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_product(team, product, "my-feature")
      create_implementation_for_product(product, name: "Impl-1")

      # Create another team with a different user
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      other_product = create_product(other_team, "MyProduct")
      create_spec_for_product(other_team, other_product, "other-feature")
      create_implementation_for_product(other_product, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      # Should only show features from the current team
      assert has_element?(view, "td", "my-feature")
      refute has_element?(view, "td", "other-feature")
    end

    test "does not show features from other products", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product1 = create_product(team, "MyProduct")
      product2 = create_product(team, "OtherProduct")
      create_spec_for_product(team, product1, "feature-1")
      create_spec_for_product(team, product2, "feature-2")
      create_implementation_for_product(product1, name: "Impl-1")
      create_implementation_for_product(product2, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "td", "feature-1")
      refute has_element?(view, "td", "feature-2")
    end
  end

  describe "context functions" do
    setup :register_and_log_in_user

    test "get_product_by_name returns correct product", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      found = Products.get_product_by_name!(team, "MyProduct")
      assert found.id == product.id
    end

    test "list_products returns all products for a team", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      create_product(team, "Product1")
      create_product(team, "Product2")

      products = Products.list_products(%Acai.Accounts.Scope{user: user}, team)
      assert length(products) == 2
    end

    test "count_active_implementations returns correct count", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_implementation_for_product(product, name: "Impl-1", is_active: true)
      create_implementation_for_product(product, name: "Impl-2", is_active: true)
      create_implementation_for_product(product, name: "Impl-3", is_active: false)

      count = Implementations.count_active_implementations(product)
      assert count == 2
    end

    test "batch_get_spec_impl_completion returns per-spec-impl data", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      spec =
        create_spec_for_product(team, product, "test-feature",
          requirements: %{
            "req.1" => %{"description" => "Req 1"},
            "req.2" => %{"description" => "Req 2"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      create_spec_impl_state(spec, impl, %{
        "req.1" => %{"status" => "completed"},
        "req.2" => %{"status" => "pending"}
      })

      # Test the batch query function
      result = Acai.Specs.batch_get_spec_impl_completion([spec], [impl])

      assert result[{spec.id, impl.id}].completed == 1
      assert result[{spec.id, impl.id}].total == 2
    end
  end

  describe "matrix inherited progress" do
    setup :register_and_log_in_user

    # product-view.MATRIX.3-1: Matrix cell shows inherited percentage for descendant with no local row
    test "matrix cell shows inherited percentage for descendant with no local row", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      # Create parent implementation with tracked branch and spec
      parent =
        create_implementation_for_product(product, name: "Parent-Impl")

      # Create tracked branch and spec for parent
      parent_tracked =
        tracked_branch_fixture(parent, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      _spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: parent_branch,
          repo_uri: "github.com/org/repo",
          requirements: %{
            "test-feature.COMP.1" => %{"requirement" => "Req 1"},
            "test-feature.COMP.2" => %{"requirement" => "Req 2"}
          }
        })

      # Create child implementation that inherits from parent
      _child =
        create_implementation_for_product(product,
          name: "Child-Impl",
          parent_implementation_id: parent.id
        )

      # Create feature_impl_state for parent only (1/2 completed = 50%)
      Acai.Specs.create_feature_impl_state("test-feature", parent, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "pending"}
        }
      })

      # Child has no local feature_impl_state row - should inherit from parent

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Both cells should show 50% (child inherits from parent)
      assert has_element?(view, "table td", "50%")

      # Should show the count for both implementations
      assert has_element?(view, "table td", "1/2")
    end

    # product-view.MATRIX.3-1: Matrix shows local percentage when both child and parent have rows
    test "matrix shows local percentage when both child and parent have rows", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      # Create parent implementation with tracked branch and spec
      parent =
        create_implementation_for_product(product, name: "Parent-Impl")

      parent_tracked =
        tracked_branch_fixture(parent, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      _spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: parent_branch,
          repo_uri: "github.com/org/repo",
          requirements: %{
            "test-feature.COMP.1" => %{"requirement" => "Req 1"},
            "test-feature.COMP.2" => %{"requirement" => "Req 2"}
          }
        })

      # Create child implementation with parent
      child =
        create_implementation_for_product(product,
          name: "Child-Impl",
          parent_implementation_id: parent.id
        )

      # Create feature_impl_state for parent (1/2 completed = 50%)
      Acai.Specs.create_feature_impl_state("test-feature", parent, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "pending"}
        }
      })

      # Create feature_impl_state for child (2/2 completed = 100%)
      Acai.Specs.create_feature_impl_state("test-feature", child, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "completed"}
        }
      })

      {:ok, view, html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # The HTML should contain both percentages
      assert html =~ "50%"
      assert html =~ "100%"

      # Should show both counts
      assert has_element?(view, "table td", "1/2")
      assert has_element?(view, "table td", "2/2")
    end
  end

  describe "matrix unavailable cells" do
    setup :register_and_log_in_user

    # product-view.MATRIX.8: Unavailable cells render n/a
    test "unavailable cells render n/a when feature not on tracked branches", %{
      conn: conn,
      user: user
    } do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      # Create spec on the product
      _spec =
        create_spec_for_product(team, product, "test-feature",
          requirements: %{
            "req.1" => %{"description" => "Req 1"}
          }
        )

      # Create implementation with NO tracked branches (feature unavailable)
      _impl_without_tracked =
        create_implementation_for_product(product, name: "No-Tracked-Branches")

      # Create implementation WITH tracked branches
      impl_with_tracked =
        create_implementation_for_product(product, name: "Has-Tracked-Branches")

      # Add tracked branch with spec for the second implementation
      tracked =
        tracked_branch_fixture(impl_with_tracked,
          repo_uri: "github.com/org/repo",
          branch_name: "main"
        )

      branch = Acai.Repo.preload(tracked, :branch).branch

      # Create spec on the tracked branch
      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: branch,
        repo_uri: "github.com/org/repo",
        requirements: %{
          "test-feature.COMP.1" => %{"requirement" => "Req 1"}
        }
      })

      {:ok, view, html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Should show n/a for the implementation without tracked branches
      assert html =~ "n/a"

      # Should show 0% (or percentage) for the implementation with tracked branches
      assert has_element?(view, "table td", "0%")
    end

    # product-view.MATRIX.8: Cells with available inherited features are clickable
    test "available inherited cells are clickable and show percentage", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      # Create parent with tracked branch and spec
      parent =
        create_implementation_for_product(product, name: "Parent-Impl")

      parent_tracked =
        tracked_branch_fixture(parent, repo_uri: "github.com/org/repo", branch_name: "main")

      parent_branch = Acai.Repo.preload(parent_tracked, :branch).branch

      _spec =
        spec_fixture(product, %{
          feature_name: "test-feature",
          branch: parent_branch,
          repo_uri: "github.com/org/repo",
          requirements: %{
            "test-feature.COMP.1" => %{"requirement" => "Req 1"},
            "test-feature.COMP.2" => %{"requirement" => "Req 2"}
          }
        })

      # Create child that inherits from parent (inherits availability)
      child =
        create_implementation_for_product(product,
          name: "Child-Impl",
          parent_implementation_id: parent.id
        )

      # Add state to parent so child can inherit progress
      Acai.Specs.create_feature_impl_state("test-feature", parent, %{
        states: %{
          "test-feature.COMP.1" => %{"status" => "completed"},
          "test-feature.COMP.2" => %{"status" => "pending"}
        }
      })

      {:ok, view, html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Should NOT show n/a since child inherits availability from parent
      refute html =~ "n/a"

      # Should show inherited percentage
      assert has_element?(view, "table td", "50%")

      # Cells should be clickable (have links)
      child_slug = Acai.Implementations.implementation_slug(child)
      assert has_element?(view, "a[href='/t/#{team.name}/i/#{child_slug}/f/test-feature']")
    end
  end

  describe "product selector" do
    setup :register_and_log_in_user

    # product-view.PRODUCT_SELECTOR.1: Dropdown lists all products in the current team
    test "selector lists all team products", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)

      # Create multiple products
      product1 = create_product(team, "Product-Alpha")
      _product2 = create_product(team, "Product-Beta")
      _product3 = create_product(team, "Product-Gamma")

      # Add specs and implementations so products load properly
      create_spec_for_product(team, product1, "feature-1")
      create_implementation_for_product(product1, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/Product-Alpha")

      # Should have the product selector container
      assert has_element?(view, "#product-selector-container")

      # Should have the trigger button
      assert has_element?(view, "#product-selector-trigger")

      # All products should be listed in the dropdown
      html = render(view)
      assert html =~ "Product-Alpha"
      assert html =~ "Product-Beta"
      assert html =~ "Product-Gamma"
    end

    # product-view.PRODUCT_SELECTOR.1: Current product is shown as selected
    test "current product is shown as selected in selector", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)

      product1 = create_product(team, "Selected-Product")
      _product2 = create_product(team, "Other-Product")

      create_spec_for_product(team, product1, "feature-1")
      create_implementation_for_product(product1, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/Selected-Product")

      # The trigger should show the current product name
      assert has_element?(view, "#product-selector-trigger", "Selected-Product")

      # The dropdown option for the current product should have 'active' class and check icon
      # Check that the selected product option has the 'active' class in its list item
      assert has_element?(
               view,
               "li a[phx-click='select_product'][phx-value-product_name='Selected-Product']"
             )

      # The selected option should have a check icon indicating it's selected
      assert has_element?(
               view,
               "a[phx-click='select_product'][phx-value-product_name='Selected-Product'] .hero-check"
             )

      # Verify the anchor has 'active' class in its class list
      # Get the anchor element and check its class attribute contains 'active'
      anchor_element =
        element(view, "a[phx-click='select_product'][phx-value-product_name='Selected-Product']")

      anchor_html = render(anchor_element)
      assert anchor_html =~ ~r/class="[^"]*active[^"]*"/
    end

    # product-view.PRODUCT_SELECTOR.2: Changing selection patches URL via handle_params
    test "switching products patches URL without full navigation", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)

      product1 = create_product(team, "First-Product")
      product2 = create_product(team, "Second-Product")

      # Add specs and implementations to both products
      create_spec_for_product(team, product1, "feature-1")
      create_implementation_for_product(product1, name: "Impl-1")

      create_spec_for_product(team, product2, "feature-2")
      create_implementation_for_product(product2, name: "Impl-2")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/First-Product")

      # Initially showing first product
      assert has_element?(view, "#product-selector-trigger", "First-Product")
      assert has_element?(view, "td", "feature-1")

      # Click on second product in selector and assert patch navigation
      view
      |> element("a[phx-click='select_product'][phx-value-product_name='Second-Product']")
      |> render_click()

      # Assert that LiveView patched to the new product URL (not a full redirect)
      assert_patch(view, ~p"/t/#{team.name}/p/Second-Product")

      # Should patch to second product (URL changes, no full reload)
      assert has_element?(view, "#product-selector-trigger", "Second-Product")
      assert has_element?(view, "td", "feature-2")
      refute has_element?(view, "td", "feature-1")
    end

    # product-view.PRODUCT_SELECTOR.2: Preserve dir param when switching products
    test "switching products preserves direction query param", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)

      product1 = create_product(team, "First-Product")
      product2 = create_product(team, "Second-Product")

      # Create implementations for ordering test with sibling children
      root1 = create_implementation_for_product(product1, name: "Root")

      # Create specs and track branches for product1
      tracked1 =
        tracked_branch_fixture(root1, repo_uri: "github.com/org/repo1", branch_name: "main")

      branch1 = Acai.Repo.preload(tracked1, :branch).branch

      spec_fixture(product1, %{
        feature_name: "feature-1",
        branch: branch1,
        repo_uri: "github.com/org/repo1"
      })

      # Create siblings with alphabetical names for product1
      create_implementation_for_product(product1,
        name: "Child-Alpha",
        parent_implementation_id: root1.id
      )

      create_implementation_for_product(product1,
        name: "Child-Beta",
        parent_implementation_id: root1.id
      )

      root2 = create_implementation_for_product(product2, name: "Root")

      # Create specs and track branches for product2
      tracked2 =
        tracked_branch_fixture(root2, repo_uri: "github.com/org/repo2", branch_name: "main")

      branch2 = Acai.Repo.preload(tracked2, :branch).branch

      spec_fixture(product2, %{
        feature_name: "feature-2",
        branch: branch2,
        repo_uri: "github.com/org/repo2"
      })

      # Create siblings with alphabetical names for product2
      create_implementation_for_product(product2,
        name: "Child-Alpha",
        parent_implementation_id: root2.id
      )

      create_implementation_for_product(product2,
        name: "Child-Beta",
        parent_implementation_id: root2.id
      )

      # Navigate with RTL direction param
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/First-Product?dir=rtl")

      # Click on second product in selector
      view
      |> element("a[phx-click='select_product'][phx-value-product_name='Second-Product']")
      |> render_click()

      # Assert that the URL patch preserved the dir=rtl query param
      assert_patch(view, ~p"/t/#{team.name}/p/Second-Product?dir=rtl")

      # Should now show second product
      assert has_element?(view, "#product-selector-trigger", "Second-Product")
      assert has_element?(view, "td", "feature-2")

      # Verify RTL ordering is still in effect on the destination product
      # (Beta should come before Alpha in RTL mode)
      html = render(view)
      [header_row] = Regex.run(~r/<thead>.*?<\/thead>/s, html)
      beta_pos = :binary.match(header_row, "Child-Beta") |> elem(0)
      alpha_pos = :binary.match(header_row, "Child-Alpha") |> elem(0)
      assert beta_pos < alpha_pos
    end

    # product-view.PRODUCT_SELECTOR.1: Selector choices stay scoped to the current team
    test "selector only shows products from current team", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)

      # Create product in current team
      product1 = create_product(team, "Team-Product")
      create_spec_for_product(team, product1, "feature-1")
      create_implementation_for_product(product1, name: "Impl-1")

      # Create another team with a product
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      _other_product = create_product(other_team, "Other-Team-Product")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/Team-Product")

      html = render(view)

      # Should show current team's product
      assert html =~ "Team-Product"

      # Should not show other team's product
      refute html =~ "Other-Team-Product"
    end
  end

  describe "matrix ordering" do
    setup :register_and_log_in_user

    # product-view.MATRIX.1-2: RTL ordering is proven at the LiveView layer
    test "RTL direction reverses sibling column order", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      # Create root implementation with tracked branch and spec
      root = create_implementation_for_product(product, name: "Root")

      tracked =
        tracked_branch_fixture(root, repo_uri: "github.com/org/repo", branch_name: "main")

      branch = Acai.Repo.preload(tracked, :branch).branch

      spec_fixture(product, %{
        feature_name: "test-feature",
        branch: branch,
        repo_uri: "github.com/org/repo"
      })

      # Create siblings with alphabetical names
      create_implementation_for_product(product,
        name: "Child-Alpha",
        parent_implementation_id: root.id
      )

      create_implementation_for_product(product,
        name: "Child-Beta",
        parent_implementation_id: root.id
      )

      # Test LTR - Alpha should come before Beta
      {:ok, view_ltr, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct?dir=ltr")
      html_ltr = render(view_ltr)
      [header_ltr] = Regex.run(~r/<thead>.*?<\/thead>/s, html_ltr)
      alpha_pos_ltr = :binary.match(header_ltr, "Child-Alpha") |> elem(0)
      beta_pos_ltr = :binary.match(header_ltr, "Child-Beta") |> elem(0)
      assert alpha_pos_ltr < beta_pos_ltr

      # Test RTL - Beta should come before Alpha
      {:ok, view_rtl, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct?dir=rtl")
      html_rtl = render(view_rtl)
      [header_rtl] = Regex.run(~r/<thead>.*?<\/thead>/s, html_rtl)
      alpha_pos_rtl = :binary.match(header_rtl, "Child-Alpha") |> elem(0)
      beta_pos_rtl = :binary.match(header_rtl, "Child-Beta") |> elem(0)
      assert beta_pos_rtl < alpha_pos_rtl
    end
  end
end
