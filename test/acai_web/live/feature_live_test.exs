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
  defp create_spec_for_feature(_team, product, feature_name, opts \\ []) do
    unique_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    # data-model.SPECS.13: Requirements stored as JSONB
    requirements =
      Keyword.get(opts, :requirements, %{
        "#{feature_name}.COMP.1" => %{
          "definition" => "Test requirement 1",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "#{feature_name}.COMP.2" => %{
          "definition" => "Test requirement 2",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      })

    spec_fixture(product, %{
      feature_name: feature_name,
      feature_description: Keyword.get(opts, :description, "Description for #{feature_name}"),
      feature_version: Keyword.get(opts, :version, "1.0.0"),
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

  # data-model.SPEC_IMPL_STATES: Create spec_impl_state with JSONB states
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
      assert has_element?(view, "h1", "my-feature")
    end

    # feature-view.ROUTING.1
    test "renders feature name with case-insensitive matching", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "MyFeature")

      # Access with lowercase URL
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/myfeature")
      # Should display the actual feature name from database
      assert has_element?(view, "h1", "MyFeature")
    end

    # feature-view.MAIN.2
    test "renders feature description when present", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      create_spec_for_feature(team, product, "my-feature",
        description: "A test feature description"
      )

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "p", "A test feature description")
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
      assert has_element?(view, "h1", "my-feature")
      # Description paragraph should not be present
      refute has_element?(view, "p", "Description")
    end

    # feature-view.MAIN.3
    test "renders implementation cards grid", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product, name: "Impl-1")

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
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product, name: "MyImpl")

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
      create_spec_for_feature(team, product, "my-feature")
      impl = create_implementation_for_product(product, name: "Deploy / Canary + EU-West 🚀")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      expected_slug = Implementations.implementation_slug(impl)

      assert expected_slug =~ ~r/^[a-z0-9-]+\+[0-9a-f]{32}$/
      assert has_element?(view, "a[href='/t/#{team.name}/i/#{expected_slug}/f/my-feature']")
    end
  end

  describe "implementation card" do
    setup :register_and_log_in_user

    # feature-view.MAIN.3
    test "shows implementation name", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      create_implementation_for_product(product, name: "Production")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "Production")
    end

    # feature-view.MAIN.3
    test "shows product name on each card", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      create_implementation_for_product(product, name: "Production")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      assert has_element?(view, "#implementations-grid", "TestProduct")
    end

    # feature-view.MAIN.3
    test "shows completion percentage", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      # Create spec with 4 requirements
      requirements = %{
        "my-feature.COMP.1" => %{
          "definition" => "Req 1",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "my-feature.COMP.2" => %{
          "definition" => "Req 2",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "my-feature.COMP.3" => %{
          "definition" => "Req 3",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "my-feature.COMP.4" => %{
          "definition" => "Req 4",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      spec = create_spec_for_feature(team, product, "my-feature", requirements: requirements)
      impl = create_implementation_for_product(product)

      # Create spec_impl_state with 2 completed (50%)
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
          "status" => "pending",
          "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
        }
        # COMP.4 has no status
      }

      create_spec_impl_state(spec, impl, states: states)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Should show 50% completion
      assert has_element?(view, "#implementations-grid", "50%")
    end

    # feature-view.MAIN.3
    test "shows 0% completion when no requirements are completed", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      create_implementation_for_product(product)

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Should show 0% completion
      assert has_element?(view, "#implementations-grid", "0%")
    end

    # feature-view.MAIN.3
    test "shows 100% completion when all requirements are completed", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")

      requirements = %{
        "my-feature.COMP.1" => %{
          "definition" => "Req 1",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }

      spec = create_spec_for_feature(team, product, "my-feature", requirements: requirements)
      impl = create_implementation_for_product(product)

      create_spec_impl_state(spec, impl, status: "completed")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")

      # Should show 100% completion
      assert has_element?(view, "#implementations-grid", "100%")
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
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      create_implementation_for_product(product, name: "MyImpl")

      # Create another team with a different user
      other_user = user_fixture()
      other_team = team_fixture()
      user_team_role_fixture(other_team, other_user, %{title: "owner"})
      other_product = create_product(other_team, "TestProduct")
      create_spec_for_feature(other_team, other_product, "my-feature")
      create_implementation_for_product(other_product, name: "OtherImpl")

      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/f/my-feature")
      # Should only show implementations from the current team
      assert has_element?(view, "#implementations-grid", "MyImpl")
      refute has_element?(view, "#implementations-grid", "OtherImpl")
    end

    test "only shows active implementations", %{conn: conn, user: user} do
      {team, _role} = create_team_with_owner(user)
      product = create_product(team, "TestProduct")
      create_spec_for_feature(team, product, "my-feature")
      create_implementation_for_product(product, name: "ActiveImpl", is_active: true)
      create_implementation_for_product(product, name: "InactiveImpl", is_active: false)

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
          "definition" => "Req 1",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "feature-1.COMP.2" => %{
          "definition" => "Req 2",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "feature-1.COMP.3" => %{
          "definition" => "Req 3",
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
end
