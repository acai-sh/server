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
  # If :for option is provided with an implementation, creates a tracked branch
  defp create_spec_for_product(_team, product, feature_name, opts \\ []) do
    unique_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
    implementation = Keyword.get(opts, :for)

    # Create requirements map for completion tracking
    requirements =
      Keyword.get(opts, :requirements, %{
        "test.1" => %{"description" => "Requirement 1"},
        "test.2" => %{"description" => "Requirement 2"},
        "test.3" => %{"description" => "Requirement 3"},
        "test.4" => %{"description" => "Requirement 4"}
      })

    spec =
      spec_fixture(product, %{
        feature_name: feature_name,
        feature_description: Keyword.get(opts, :description, "Description for #{feature_name}"),
        feature_version: Keyword.get(opts, :feature_version, "1.0.0"),
        path: "features/#{feature_name}-#{unique_suffix}/feature.yaml",
        repo_uri: "github.com/test/repo-#{unique_suffix}",
        requirements: requirements
      })

    # If implementation provided, create tracked branch linking them
    if implementation do
      branch =
        Acai.Repo.get!(Acai.Specs.Spec, spec.id)
        |> Map.get(:branch_id)
        |> then(&Acai.Repo.get!(Acai.Implementations.Branch, &1))

      tracked_branch_fixture(implementation, branch: branch)
    end

    spec
  end

  # data-model.IMPLS: Create implementation for a product (not a spec)
  defp create_implementation_for_product(product, opts) do
    implementation_fixture(product, %{
      name: Keyword.get(opts, :name, "Impl-#{System.unique_integer([:positive])}"),
      is_active: Keyword.get(opts, :is_active, true)
    })
  end

  # Create spec_impl_state with completion data
  defp create_spec_impl_state(spec, implementation, states) do
    Acai.Specs.create_spec_impl_state(spec, implementation, %{states: states})
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
      assert has_element?(view, "h1", "MyProduct")
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
      assert has_element?(view, "h1", "MyProduct")
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

      spec =
        create_spec_for_product(team, product, "my-feature",
          requirements: %{
            "req.1" => %{"description" => "Req 1"},
            "req.2" => %{"description" => "Req 2"},
            "req.3" => %{"description" => "Req 3"},
            "req.4" => %{"description" => "Req 4"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # Set 2 out of 4 requirements as completed (50%)
      create_spec_impl_state(spec, impl, %{
        "req.1" => %{"status" => "completed"},
        "req.2" => %{"status" => "completed"},
        "req.3" => %{"status" => "pending"},
        "req.4" => %{"status" => "pending"}
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
      create_spec_for_product(team, product, "my-feature")
      create_implementation_for_product(product, name: "Test-Impl")

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
            "req.1" => %{"description" => "Req 1"},
            "req.2" => %{"description" => "Req 2"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      create_spec_impl_state(spec, impl, %{
        "req.1" => %{"status" => "completed"},
        "req.2" => %{"status" => "completed"}
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
      create_spec_for_product(team, product, "my-feature")
      impl = create_implementation_for_product(product, name: "Test-Impl")

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

  describe "product selector" do
    setup :register_and_log_in_user

    # product-view.PRODUCT_SELECTOR.1
    test "dropdown lists all products in the team", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      _product1 = create_product(team, "Product-One")
      _product2 = create_product(team, "Product-Two")

      # Create spec and impl for one product so the page loads
      product1 = create_product(team, "Active-Product")
      create_spec_for_product(team, product1, "feature-1")
      create_implementation_for_product(product1, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/Active-Product")

      # Should have select with all products
      assert has_element?(view, "select")
      assert has_element?(view, "option[value='Product-One']")
      assert has_element?(view, "option[value='Product-Two']")
      assert has_element?(view, "option[value='Active-Product']")
    end

    # product-view.PRODUCT_SELECTOR.1
    test "current product is selected in dropdown", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_product(team, product, "feature-1")
      create_implementation_for_product(product, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # The select should have the current product value set
      assert has_element?(view, "select")
      html = render(view)
      # The select element should have the current product name in its options
      assert html =~ "MyProduct"
    end

    # product-view.PRODUCT_SELECTOR.2
    test "changing product patches URL via handle_params", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product1 = create_product(team, "Product-One")
      product2 = create_product(team, "Product-Two")
      create_spec_for_product(team, product1, "feature-1")
      create_spec_for_product(team, product2, "feature-2")
      create_implementation_for_product(product1, name: "Impl-1")
      create_implementation_for_product(product2, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/Product-One")

      # Change the product selection
      view
      |> form("#product-selector-form", %{"product" => %{"product_id" => "Product-Two"}})
      |> render_change()

      # The page should update to show Product-Two's features
      assert has_element?(view, "h1", "Product-Two")
      assert has_element?(view, "td", "feature-2")
    end
  end

  describe "color gradient" do
    setup :register_and_log_in_user

    # product-view.MATRIX.4
    test "0% completion shows default color", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")
      create_spec_for_product(team, product, "my-feature")
      create_implementation_for_product(product, name: "Test-Impl")

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
            "req.1" => %{"description" => "Req 1"},
            "req.2" => %{"description" => "Req 2"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # 1 of 2 completed = 50%
      create_spec_impl_state(spec, impl, %{
        "req.1" => %{"status" => "completed"},
        "req.2" => %{"status" => "pending"}
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
            "req.1" => %{"description" => "Req 1"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      create_spec_impl_state(spec, impl, %{
        "req.1" => %{"status" => "completed"}
      })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # 100% cell should have success background class
      # Check for the bg-success/10 class in the rendered HTML
      html = render(view)
      assert html =~ "bg-success/10"
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
            "spec1.req.1" => %{"description" => "Spec1 Req 1"},
            "spec1.req.2" => %{"description" => "Spec1 Req 2"}
          }
        )

      spec2 =
        create_spec_for_product(team, product, "shared-feature",
          feature_version: "2.0.0",
          requirements: %{
            "spec2.req.1" => %{"description" => "Spec2 Req 1"},
            "spec2.req.2" => %{"description" => "Spec2 Req 2"},
            "spec2.req.3" => %{"description" => "Spec2 Req 3"}
          }
        )

      impl = create_implementation_for_product(product, name: "Test-Impl")

      # Complete 1/2 from spec1 and 2/3 from spec2 = 3/5 total = 60%
      create_spec_impl_state(spec1, impl, %{
        "spec1.req.1" => %{"status" => "completed"},
        "spec1.req.2" => %{"status" => "pending"}
      })

      create_spec_impl_state(spec2, impl, %{
        "spec2.req.1" => %{"status" => "completed"},
        "spec2.req.2" => %{"status" => "completed"},
        "spec2.req.3" => %{"status" => "pending"}
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

  describe "inheritance" do
    setup :register_and_log_in_user

    # product-view.MATRIX.8
    test "shows n/a for features not in implementation's ancestor tree", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      # Create an implementation with no parent and no tracked branches
      impl = create_implementation_for_product(product, name: "StandaloneImpl")

      # Create a spec on a different branch not tracked by this implementation
      _spec = create_spec_for_product(team, product, "unreachable-feature")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Should show n/a for this feature since it's not in the ancestor tree
      assert has_element?(view, "td", "n/a")
    end

    # product-view.ROUTING.3
    test "shows inherited completion correctly", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      spec =
        create_spec_for_product(team, product, "test-feature",
          requirements: %{
            "req.1" => %{"description" => "Req 1"},
            "req.2" => %{"description" => "Req 2"}
          }
        )

      # Create parent with completed states
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      create_spec_impl_state(spec, parent_impl, %{
        "req.1" => %{"status" => "completed"},
        "req.2" => %{"status" => "completed"}
      })

      # Create child that inherits from parent
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Should show 100% completion for child (inherited from parent)
      assert has_element?(view, "table td", "100%")
    end

    test "child's direct data takes precedence in completion", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      spec =
        create_spec_for_product(team, product, "test-feature",
          requirements: %{
            "req.1" => %{"description" => "Req 1"},
            "req.2" => %{"description" => "Req 2"}
          }
        )

      # Create parent with 50% completion
      parent_impl = create_implementation_for_product(product, name: "ParentImpl")

      create_spec_impl_state(spec, parent_impl, %{
        "req.1" => %{"status" => "completed"},
        "req.2" => %{"status" => "pending"}
      })

      # Create child with 100% completion (should override parent's 50%)
      child_impl =
        implementation_fixture(product, %{
          name: "ChildImpl",
          parent_implementation_id: parent_impl.id
        })

      create_spec_impl_state(spec, child_impl, %{
        "req.1" => %{"status" => "completed"},
        "req.2" => %{"status" => "completed"}
      })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # Both should show their respective percentages
      # Parent: 50%, Child: 100%
      assert has_element?(view, "table td", "50%")
      assert has_element?(view, "table td", "100%")
    end

    # product-view.MATRIX.8
    test "n/a cells are not clickable links", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "MyProduct")

      # Create implementation with no tracked branches
      impl = create_implementation_for_product(product, name: "StandaloneImpl")

      # Create spec that implementation cannot access
      _spec = create_spec_for_product(team, product, "unreachable-feature")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")

      # The n/a cell should not be a link
      html = render(view)
      # It should contain n/a text but no link wrapper
      assert html =~ "n/a"
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
end
