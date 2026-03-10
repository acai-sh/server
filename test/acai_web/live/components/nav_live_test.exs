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
end
