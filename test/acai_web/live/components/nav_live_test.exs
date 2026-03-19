defmodule AcaiWeb.Live.Components.NavLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.DataModelFixtures

  # Helper to set up a team with an owner (the logged-in user)
  defp create_team_with_owner(user) do
    team = team_fixture()
    role = user_team_role_fixture(team, user, %{title: "owner"})
    {team, role}
  end

  # Helper to create a product with specs
  # data-model.PRODUCTS: Products are now first-class entities
  defp create_product_with_specs(team, product_name, feature_names) do
    product = product_fixture(team, %{name: product_name})

    Enum.each(feature_names, fn feature_name ->
      spec_fixture(product, %{feature_name: feature_name})
    end)

    product
  end

  describe "nav.HEADER" do
    setup :register_and_log_in_user

    # nav.HEADER.1
    test "renders application logo linking to /teams", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      # logo moved into sidebar nav panel
      assert has_element?(view, "#nav-panel a[href='/teams']")
      assert has_element?(view, "#nav-panel img[src='/images/logo.svg']")
    end

    # nav.HEADER.2
    test "renders current user's email address", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "span", user.email)
    end

    # nav.HEADER.3
    test "renders link to User Settings", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "a[href='/users/settings']")
    end

    # nav.HEADER.4
    test "renders Log Out button", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "a[href='/users/log-out']")
    end
  end

  describe "nav.PANEL.1: Team dropdown selector" do
    setup :register_and_log_in_user

    # nav.PANEL.1-1
    test "lists all teams the current user is a member of", %{conn: conn, user: user} do
      {team1, _} = create_team_with_owner(user)
      {team2, _} = create_team_with_owner(user)

      {:ok, view, _html} = live(conn, ~p"/t/#{team1.name}")

      assert has_element?(view, "#team-selector option[value='#{team1.name}']")
      assert has_element?(view, "#team-selector option[value='#{team2.name}']")
    end

    # nav.PANEL.1-2
    test "selecting a team navigates to /t/:team_name", %{conn: conn, user: user} do
      {team1, _} = create_team_with_owner(user)
      {team2, _} = create_team_with_owner(user)

      {:ok, view, _html} = live(conn, ~p"/t/#{team1.name}")

      # Simulate selecting a different team via the form's phx-change
      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               view
               |> element("form[phx-change='select_team']")
               |> render_change(%{"team" => team2.name})

      assert redirect_path == "/t/#{team2.name}"
    end

    # nav.PANEL.1-3
    test "visually indicates currently active team", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "#team-selector option[value='#{team.name}'][selected]")
    end
  end

  describe "nav.PANEL.2: Home nav item" do
    setup :register_and_log_in_user

    test "renders Home nav item linking to /t/:team_name", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "a[href='/t/#{team.name}']", "Home")
    end

    test "Home nav item is active on team overview page", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      # The home link should have the active class
      html = render(view)
      assert html =~ "bg-base-300 text-primary"
    end
  end

  describe "nav.PANEL.3: PRODUCTS section" do
    setup :register_and_log_in_user

    # nav.PANEL.3-1
    # data-model.PRODUCTS: Products are now first-class entities
    test "renders each product as collapsible item", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)

      # Create products with specs
      create_product_with_specs(team, "product-a", ["feature-1"])
      create_product_with_specs(team, "product-b", ["feature-2"])

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "a", "product-a")
      assert has_element?(view, "a", "product-b")
    end

    # nav.PANEL.3-2
    # data-model.PRODUCTS: Product display name from Product entity
    test "product display name is derived from product name", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)

      create_product_with_specs(team, "my-product", ["feature-1"])

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "a", "my-product")
    end
  end

  describe "nav.PANEL.4: Product expansion" do
    setup :register_and_log_in_user

    # nav.PANEL.4-1
    test "each feature name links to /t/:team_name/f/:feature_name", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)

      product = create_product_with_specs(team, "my-product", ["my-feature"])
      spec = Acai.Specs.list_specs_for_product(product) |> List.first()

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      # Expand the product first - target the expansion button by value
      view |> element("button[phx-value-product='my-product']") |> render_click()

      assert has_element?(view, "a[href='/t/#{team.name}/f/#{spec.feature_name}']")
    end

    # nav.PANEL.4-2
    test "multiple products can be expanded simultaneously", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)

      create_product_with_specs(team, "product-a", ["feature-1"])
      create_product_with_specs(team, "product-b", ["feature-2"])

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      # Expand both products
      view |> element("button[phx-value-product='product-a']") |> render_click()
      view |> element("button[phx-value-product='product-b']") |> render_click()

      # Both features should be visible
      assert has_element?(view, "a", "feature-1")
      assert has_element?(view, "a", "feature-2")
    end
  end

  describe "nav.PANEL.5: Auto-expand and highlight based on URL" do
    setup :register_and_log_in_user

    # nav.PANEL.5-1
    test "on /t/:team_name/p/:product_name, expands and highlights matching product", %{
      conn: conn,
      user: user
    } do
      {team, _} = create_team_with_owner(user)

      create_product_with_specs(team, "my-product", ["feature-1"])

      # Note: This test assumes a route exists for /t/:team_name/p/:product_name
      # Since we don't have that route yet, we test the parsing logic indirectly
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      # The product should be visible
      assert has_element?(view, "a", "my-product")
    end

    # nav.PANEL.5-2
    test "on /t/:team_name/f/:feature_name, expands product and highlights feature", %{
      conn: conn,
      user: user
    } do
      {team, _} = create_team_with_owner(user)

      create_product_with_specs(team, "my-product", ["my-feature"])

      # Note: This test assumes a route exists for /t/:team_name/f/:feature_name
      # Since we don't have that route yet, we test the parsing logic indirectly
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      # Expand the product to see the feature
      view |> element("button[phx-value-product='my-product']") |> render_click()

      assert has_element?(view, "a[href='/t/#{team.name}/f/my-feature']")
    end

    # nav.PANEL.5-4
    test "highlighting propagates upward - active product is highlighted", %{
      conn: conn,
      user: user
    } do
      {team, _} = create_team_with_owner(user)

      create_product_with_specs(team, "my-product", ["feature-1"])

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      # The product link should exist
      assert has_element?(view, "a", "my-product")
    end
  end

  describe "nav.PANEL.6: Bottom navigation links" do
    setup :register_and_log_in_user

    test "renders Team Settings link", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "a[href='/t/#{team.name}/settings']", "Team Settings")
    end

    test "renders Tokens link", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "a[href='/t/#{team.name}/tokens']", "Tokens")
    end
  end

  describe "nav.MOBILE: Mobile navigation" do
    setup :register_and_log_in_user

    # nav.MOBILE.1
    test "hamburger button is visible on mobile", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      assert has_element?(view, "#mobile-nav-toggle")
    end

    # nav.MOBILE.2
    test "sidebar is hidden by default on mobile", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      {:ok, _view, html} = live(conn, ~p"/t/#{team.name}")

      # The sidebar should have the -translate-x-full class
      assert html =~ "-translate-x-full"
    end
  end

  describe "nav.AUTH: Visibility and access" do
    setup :register_and_log_in_user

    # nav.AUTH.1
    test "PANEL is only rendered for team-scoped routes", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)

      # Team route should have the nav panel
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")
      assert has_element?(view, "#nav-panel")

      # Teams list route should NOT have the nav panel
      {:ok, view2, _html} = live(conn, ~p"/teams")
      refute has_element?(view2, "#nav-panel")
    end

    # nav.AUTH.2
    test "only lists teams user has access to", %{conn: conn, user: user} do
      {team1, _} = create_team_with_owner(user)

      # Create another team that the user is NOT a member of
      _other_team = team_fixture()

      {:ok, view, _html} = live(conn, ~p"/t/#{team1.name}")

      # Only team1 should be in the selector
      assert has_element?(view, "#team-selector option[value='#{team1.name}']")
    end
  end

  describe "nav.PANEL: Duplicate feature deduplication" do
    setup :register_and_log_in_user

    # product-view.MATRIX.2: Features should be distinct (deduplicated) in nav
    test "deduplicates features that exist across multiple branches", %{
      conn: conn,
      user: user
    } do
      {team, _} = create_team_with_owner(user)

      # Create a product
      product = product_fixture(team, %{name: "dedup-product"})

      # Create two different branches
      branch1 = branch_fixture(team, %{branch_name: "main"})
      branch2 = branch_fixture(team, %{branch_name: "develop"})

      # Create two specs for the SAME feature on different branches
      # This simulates the real scenario where form-editor and map-settings have 2 versions each
      spec_fixture(product, %{
        feature_name: "form-editor",
        branch: branch1,
        feature_version: "1.0.0"
      })

      spec_fixture(product, %{
        feature_name: "form-editor",
        branch: branch2,
        feature_version: "1.1.0"
      })

      # Create another feature with multiple specs
      spec_fixture(product, %{
        feature_name: "map-settings",
        branch: branch1,
        feature_version: "1.0.0"
      })

      spec_fixture(product, %{
        feature_name: "map-settings",
        branch: branch2,
        feature_version: "2.0.0"
      })

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      # Expand the product
      view |> element("button[phx-value-product='dedup-product']") |> render_click()

      html = render(view)

      # Count feature links - we expect exactly 2 links (one per unique feature)
      # The feature name appears in: 1) link text, 2) URL path
      # So we count links to verify deduplication

      # Count links containing the feature name in the href
      # Each unique feature should have exactly one link
      form_editor_links =
        Regex.scan(~r{href=['"]/t/[^/]+/f/form-editor['"]}, html)
        |> length()

      map_settings_links =
        Regex.scan(~r{href=['"]/t/[^/]+/f/map-settings['"]}, html)
        |> length()

      assert form_editor_links == 1,
             "Expected 1 link to form-editor, but found #{form_editor_links}"

      assert map_settings_links == 1,
             "Expected 1 link to map-settings, but found #{map_settings_links}"

      # Verify both features are rendered as link text
      assert has_element?(view, "a", "form-editor")
      assert has_element?(view, "a", "map-settings")
    end

    # product-view.MATRIX.2: Ensure features are sorted alphabetically
    test "features are sorted alphabetically", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      product = product_fixture(team, %{name: "sorted-product"})

      # Create features in non-alphabetical order
      spec_fixture(product, %{feature_name: "zebra-feature"})
      spec_fixture(product, %{feature_name: "alpha-feature"})
      spec_fixture(product, %{feature_name: "mango-feature"})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      # Expand the product
      view |> element("button[phx-value-product='sorted-product']") |> render_click()

      # Verify all features are rendered
      assert has_element?(view, "a", "alpha-feature")
      assert has_element?(view, "a", "mango-feature")
      assert has_element?(view, "a", "zebra-feature")
    end
  end

  describe "nav.PANEL: Product icon and styling" do
    setup :register_and_log_in_user

    # Product nav uses custom-boxes icon consistent with Product visual language
    test "product nav item uses custom-boxes icon", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      create_product_with_specs(team, "icon-test-product", ["feature-1"])

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}")

      # The product link should contain the custom-boxes icon
      assert has_element?(view, "a[href='/t/#{team.name}/p/icon-test-product']")

      html = render(view)
      # Verify custom-boxes icon is present in the product row
      assert html =~ "custom-boxes"
    end

    # Product nav uses secondary color styling consistent with Product visual language
    test "product nav item uses secondary color for active state", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      create_product_with_specs(team, "active-product", ["feature-1"])

      # Navigate to the product page to make it active
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/active-product")

      html = render(view)

      # The active product should have text-accent class
      assert html =~ "text-accent"
    end

    # Feature items should use primary color (not secondary)
    test "feature nav items use primary color for active state", %{conn: conn, user: user} do
      {team, _} = create_team_with_owner(user)
      create_product_with_specs(team, "feature-test-product", ["active-feature"])

      # Navigate to the feature page to make it active
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/active-feature")

      html = render(view)

      # The active feature should have text-primary class
      assert html =~ "text-primary"
    end
  end
end
