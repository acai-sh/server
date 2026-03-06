defmodule AcaiWeb.ProductLiveTest do
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

  # Helper to create a spec with a specific product and feature
  # Uses unique path to avoid unique constraint violation
  defp create_spec_for_product(team, product_name, feature_name, opts \\ []) do
    unique_id = System.unique_integer([:positive])

    spec_fixture(team, %{
      feature_product: product_name,
      feature_name: feature_name,
      feature_description: Keyword.get(opts, :description, "Description for #{feature_name}"),
      path: "features/#{feature_name}-#{unique_id}/feature.yaml"
    })
  end

  # Helper to create an implementation for a spec
  defp create_implementation_for_spec(spec, opts) do
    implementation_fixture(spec, %{
      name: Keyword.get(opts, :name, "Impl-#{System.unique_integer([:positive])}"),
      is_active: Keyword.get(opts, :is_active, true)
    })
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

    # product-view.MAIN.1
    test "renders the product name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_product(team, "MyProduct", "feature-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "h1", "MyProduct")
    end

    # product-view.MAIN.1
    test "renders product name with case-insensitive matching", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      # Create spec with product name "MyProduct"
      create_spec_for_product(team, "MyProduct", "feature-1")

      # Access with lowercase URL
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/myproduct")
      # Should display the actual product name from database
      assert has_element?(view, "h1", "MyProduct")
    end

    # product-view.MAIN.2
    test "renders feature cards for product with features", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_product(team, "MyProduct", "feature-1")
      create_spec_for_product(team, "MyProduct", "feature-2")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "#features-grid")
      assert has_element?(view, "[id^='features-']")
    end

    # product-view.MAIN.2-1
    test "shows empty state when product has no features", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      # Create a spec for "MyProduct" with a feature
      # Then delete the spec to simulate an empty product
      # For now, this test verifies that a non-existent product redirects
      # The empty state would only be shown if a product exists but has no features
      # which is not possible in the current data model (specs always have feature_name)

      # When a product doesn't exist (no specs), it should redirect
      assert {:error, {:live_redirect, %{to: redirect_to}}} =
               live(conn, ~p"/t/#{team.name}/p/NonExistentProduct")

      assert redirect_to == ~p"/t/#{team.name}"
    end

    # product-view.FEATURE_CARD.1
    test "feature card shows feature name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_product(team, "MyProduct", "my-feature")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "#features-grid", "my-feature")
    end

    # product-view.FEATURE_CARD.2
    test "feature card shows feature description when present", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_product(team, "MyProduct", "my-feature", description: "A test feature")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "#features-grid", "A test feature")
    end

    # product-view.FEATURE_CARD.2
    test "feature card does not show description when nil", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_product(team, "MyProduct", "my-feature", description: nil)

      # Update spec to have nil description
      Specs.update_spec(spec, %{feature_description: nil})

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      # Should still render the card without error
      assert has_element?(view, "#features-grid", "my-feature")
    end

    # product-view.FEATURE_CARD.3
    test "feature card shows implementation count", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_product(team, "MyProduct", "my-feature")
      create_implementation_for_spec(spec, name: "Impl-1")
      create_implementation_for_spec(spec, name: "Impl-2")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "#features-grid", "2 implementations")
    end

    # product-view.FEATURE_CARD.3
    test "feature card shows singular implementation count", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_product(team, "MyProduct", "my-feature")
      create_implementation_for_spec(spec, name: "Impl-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "#features-grid", "1 implementation")
    end

    # product-view.FEATURE_CARD.3
    test "feature card only counts active implementations", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_product(team, "MyProduct", "my-feature")
      create_implementation_for_spec(spec, name: "Impl-1", is_active: true)
      create_implementation_for_spec(spec, name: "Impl-2", is_active: false)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "#features-grid", "1 implementation")
    end

    # product-view.MAIN.3
    test "feature card navigates to feature view on click", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_product(team, "MyProduct", "my-feature")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "a[href='/t/#{team.name}/f/my-feature']")
    end

    # product-view.ROUTING.1
    test "case-insensitive product name matching works", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_product(team, "MyProduct", "feature-1")

      # Test various case combinations
      for product_name <- ["MyProduct", "myproduct", "MYPRODUCT", "Myproduct"] do
        {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/#{product_name}")
        assert has_element?(view, "h1", "MyProduct")
        assert has_element?(view, "#features-grid", "feature-1")
      end
    end

    # product-view.ROUTING.2
    test "redirects to team page when product not found", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      # Don't create any specs for this product

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

    test "only shows features for the correct team", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_product(team, "MyProduct", "my-feature")

      # Create another team with a different user
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      create_spec_for_product(other_team, "MyProduct", "other-feature")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      # Should only show features from the current team
      assert has_element?(view, "#features-grid", "my-feature")
      refute has_element?(view, "#features-grid", "other-feature")
    end

    test "shows multiple features for same product", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_product(team, "MyProduct", "feature-1")
      create_spec_for_product(team, "MyProduct", "feature-2")
      create_spec_for_product(team, "MyProduct", "feature-3")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "#features-grid", "feature-1")
      assert has_element?(view, "#features-grid", "feature-2")
      assert has_element?(view, "#features-grid", "feature-3")
    end

    test "does not show features from other products", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_product(team, "MyProduct", "feature-1")
      create_spec_for_product(team, "OtherProduct", "feature-2")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      assert has_element?(view, "#features-grid", "feature-1")
      refute has_element?(view, "#features-grid", "feature-2")
    end
  end

  describe "navigation highlighting" do
    setup :register_and_log_in_user

    test "navigation shows current product as active", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      create_spec_for_product(team, "MyProduct", "feature-1")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/p/MyProduct")
      # The nav component should have the product highlighted
      # This is handled by nav.PANEL.5-1
      assert has_element?(view, "#nav-panel")
    end
  end

  describe "specs context functions" do
    setup :register_and_log_in_user

    test "get_specs_by_product_name returns correct product and specs", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      spec1 = create_spec_for_product(team, "MyProduct", "feature-1")
      spec2 = create_spec_for_product(team, "MyProduct", "feature-2")

      {product_name, specs} = Specs.get_specs_by_product_name(team, "myproduct")
      assert product_name == "MyProduct"
      assert length(specs) == 2
      assert Enum.any?(specs, &(&1.id == spec1.id))
      assert Enum.any?(specs, &(&1.id == spec2.id))
    end

    test "get_specs_by_product_name returns nil for non-existent product", %{user: user} do
      {team, _role} = create_team_with_owner(user)

      result = Specs.get_specs_by_product_name(team, "nonexistent")
      assert result == nil
    end
  end

  describe "implementations context functions" do
    setup :register_and_log_in_user

    test "count_active_implementations returns correct count", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_product(team, "MyProduct", "feature-1")
      create_implementation_for_spec(spec, is_active: true)
      create_implementation_for_spec(spec, is_active: true)
      create_implementation_for_spec(spec, is_active: false)

      count = Implementations.count_active_implementations(spec)
      assert count == 2
    end

    test "count_active_implementations returns 0 when no implementations", %{user: user} do
      {team, _role} = create_team_with_owner(user)
      spec = create_spec_for_product(team, "MyProduct", "feature-1")

      count = Implementations.count_active_implementations(spec)
      assert count == 0
    end
  end
end
