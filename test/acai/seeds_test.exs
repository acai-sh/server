defmodule Acai.SeedsTest do
  @moduledoc """
  Tests for priv/repo/seeds.exs seed data generation.
  Verifies the mapperoni data model with:
  - Team: mapperoni
  - Products: site, api
  - Site specs: map-editor, map-viewer, project-view, data-explorer, form-editor, field-settings, map-settings
  - API specs: core-api, push-api
  - Specs with JSONB requirements
  - FeatureImplState and FeatureImplRef tables
  - Implementations belonging to Products
  """

  use Acai.DataCase, async: false

  alias Acai.Repo
  alias Acai.Accounts
  alias Acai.Teams
  alias Acai.Products.Product
  alias Acai.Specs.{Spec, FeatureImplState, FeatureBranchRef}
  alias Acai.Implementations.{Implementation, TrackedBranch, Branch}

  setup do
    # Clean slate for each test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Run seeds using the module
    Acai.Seeds.run(silent: true)

    :ok
  end

  defp get_product!(team_name, product_name) do
    team = Repo.get_by!(Teams.Team, name: team_name)
    Repo.get_by!(Product, team_id: team.id, name: product_name)
  end

  defp get_spec!(product, feature_name) do
    Repo.get_by!(Spec, product_id: product.id, feature_name: feature_name)
  end

  describe "user seeding" do
    test "creates owner user" do
      user = Accounts.get_user_by_email("owner@mapperoni.com")
      assert user != nil
    end

    test "creates developer user" do
      user = Accounts.get_user_by_email("developer@mapperoni.com")
      assert user != nil
    end

    test "creates readonly user" do
      user = Accounts.get_user_by_email("readonly@mapperoni.com")
      assert user != nil
    end

    test "idempotent: running seeds twice doesn't duplicate users" do
      user_count_before = Repo.aggregate(Accounts.User, :count)
      Acai.Seeds.run(silent: true)
      user_count_after = Repo.aggregate(Accounts.User, :count)
      assert user_count_before == user_count_after
    end
  end

  describe "team seeding" do
    test "creates mapperoni team" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      assert team != nil
    end

    test "assigns owner role to owner user" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      owner = Accounts.get_user_by_email("owner@mapperoni.com")

      role = Repo.get_by(Teams.UserTeamRole, team_id: team.id, user_id: owner.id)
      assert role != nil
      assert role.title == "owner"
    end

    test "assigns developer role to developer user" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      dev = Accounts.get_user_by_email("developer@mapperoni.com")

      role = Repo.get_by(Teams.UserTeamRole, team_id: team.id, user_id: dev.id)
      assert role != nil
      assert role.title == "developer"
    end

    test "idempotent: running seeds twice doesn't duplicate teams" do
      team_count_before = Repo.aggregate(Teams.Team, :count)
      Acai.Seeds.run(silent: true)
      team_count_after = Repo.aggregate(Teams.Team, :count)
      assert team_count_before == team_count_after
    end
  end

  # data-model.PRODUCTS
  describe "product seeding" do
    test "creates site product" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      product = Repo.get_by(Product, team_id: team.id, name: "site")
      assert product != nil

      assert product.description ==
               "Mapperoni web application - map-based survey builder and viewer"
    end

    test "creates api product" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      product = Repo.get_by(Product, team_id: team.id, name: "api")
      assert product != nil
      assert product.description == "Mapperoni API - backend services for maps, forms, and data"
    end

    test "idempotent: running seeds twice doesn't duplicate products" do
      product_count_before = Repo.aggregate(Product, :count)
      Acai.Seeds.run(silent: true)
      product_count_after = Repo.aggregate(Product, :count)
      assert product_count_before == product_count_after
    end
  end

  # data-model.SPECS
  # data-model.SPECS.13: Requirements stored as JSONB
  describe "site spec seeding" do
    test "creates map-editor spec" do
      product = get_product!("mapperoni", "site")
      spec = get_spec!(product, "map-editor")
      assert spec != nil

      assert spec.feature_description ==
               "Interactive map creation and editing interface for building shareable maps"
    end

    test "creates map-viewer spec" do
      product = get_product!("mapperoni", "site")
      spec = get_spec!(product, "map-viewer")
      assert spec != nil
    end

    test "creates form-editor spec" do
      product = get_product!("mapperoni", "site")
      spec = get_spec!(product, "form-editor")
      assert spec != nil
    end

    test "map-editor spec has JSONB requirements" do
      product = get_product!("mapperoni", "site")
      spec = get_spec!(product, "map-editor")

      # data-model.SPECS.13-1: Requirements keyed by ACID
      assert is_map(spec.requirements)
      assert Map.has_key?(spec.requirements, "map-editor.CANVAS.1")
      assert Map.has_key?(spec.requirements, "map-editor.LAYERS.1")
      assert Map.has_key?(spec.requirements, "map-editor.MARKERS.1")
    end

    test "requirement JSONB has correct structure" do
      product = get_product!("mapperoni", "site")
      spec = get_spec!(product, "map-editor")

      req = spec.requirements["map-editor.CANVAS.1"]

      assert req["definition"] ==
               "Users must be able to create a new map with a name and description."

      assert req["note"] == "Map names must be unique within a project"
      assert req["is_deprecated"] == false
      assert req["replaced_by"] == []
    end

    test "site spec belongs to site product" do
      product = get_product!("mapperoni", "site")
      spec = get_spec!(product, "map-editor")

      # data-model.SPECS.14-1: spec belongs to product
      spec_product = Repo.get(Product, spec.product_id)
      assert spec_product != nil
      assert spec_product.name == "site"
    end
  end

  describe "api spec seeding" do
    test "creates core-api spec" do
      product = get_product!("mapperoni", "api")
      spec = get_spec!(product, "core-api")
      assert spec != nil
    end

    test "creates push-api spec" do
      product = get_product!("mapperoni", "api")
      spec = get_spec!(product, "push-api")
      assert spec != nil
    end

    test "push-api spec has JSONB requirements" do
      product = get_product!("mapperoni", "api")
      spec = get_spec!(product, "push-api")

      assert is_map(spec.requirements)
      assert Map.has_key?(spec.requirements, "push-api.SPEC.1")
      assert Map.has_key?(spec.requirements, "push-api.STATE.1")
    end

    test "api spec belongs to api product" do
      product = get_product!("mapperoni", "api")
      spec = get_spec!(product, "push-api")

      spec_product = Repo.get(Product, spec.product_id)
      assert spec_product != nil
      assert spec_product.name == "api"
    end

    test "idempotent: running seeds twice doesn't duplicate specs" do
      spec_count_before = Repo.aggregate(Spec, :count)
      Acai.Seeds.run(silent: true)
      spec_count_after = Repo.aggregate(Spec, :count)
      assert spec_count_before == spec_count_after
    end
  end

  # data-model.IMPLS
  describe "implementation seeding" do
    test "creates production implementation for site" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      product = Repo.get_by(Product, team_id: team.id, name: "site")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "production")

      assert impl != nil
      assert impl.is_active == true
    end

    test "creates staging implementation for site" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      product = Repo.get_by(Product, team_id: team.id, name: "site")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "staging")

      assert impl != nil
    end

    test "creates production implementation for api" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      product = Repo.get_by(Product, team_id: team.id, name: "api")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "production")

      assert impl != nil
    end

    test "implementation belongs to correct team" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      product = Repo.get_by(Product, team_id: team.id, name: "site")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "production")

      assert impl.team_id == team.id
    end

    test "idempotent: running seeds twice doesn't duplicate implementations" do
      impl_count_before = Repo.aggregate(Implementation, :count)
      Acai.Seeds.run(silent: true)
      impl_count_after = Repo.aggregate(Implementation, :count)
      assert impl_count_before == impl_count_after
    end
  end

  # data-model.BRANCHES
  describe "tracked branch seeding" do
    test "creates tracked branches for implementations" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      product = Repo.get_by(Product, team_id: team.id, name: "site")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "production")

      branches = Repo.all(from b in TrackedBranch, where: b.implementation_id == ^impl.id)
      assert length(branches) > 0
    end

    test "tracked branch links to branch with last_seen_commit" do
      team = Repo.get_by(Teams.Team, name: "mapperoni")
      product = Repo.get_by(Product, team_id: team.id, name: "site")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "production")

      tracked_branch =
        Repo.get_by(TrackedBranch,
          implementation_id: impl.id,
          repo_uri: "github.com/mapperoni/mapperoni-site"
        )
        |> Repo.preload(:branch)

      assert tracked_branch != nil
      assert tracked_branch.branch != nil
      assert tracked_branch.branch.last_seen_commit != nil
    end

    test "idempotent: running seeds twice doesn't duplicate tracked branches" do
      branch_count_before = Repo.aggregate(TrackedBranch, :count)
      Acai.Seeds.run(silent: true)
      branch_count_after = Repo.aggregate(TrackedBranch, :count)
      assert branch_count_before == branch_count_after
    end
  end

  # data-model.FEATURE_IMPL_STATES
  describe "feature_impl_state seeding" do
    test "creates feature_impl_state for map-editor spec and production impl" do
      product = get_product!("mapperoni", "site")
      spec = get_spec!(product, "map-editor")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "production")

      state =
        Repo.get_by(FeatureImplState, feature_name: spec.feature_name, implementation_id: impl.id)

      assert state != nil
    end

    test "feature_impl_state has JSONB states keyed by ACID" do
      product = get_product!("mapperoni", "site")
      spec = get_spec!(product, "map-editor")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "production")

      state =
        Repo.get_by(FeatureImplState, feature_name: spec.feature_name, implementation_id: impl.id)

      # data-model.FEATURE_IMPL_STATES.4: States keyed by ACID
      assert is_map(state.states)
      assert Map.has_key?(state.states, "map-editor.CANVAS.1")
      assert Map.has_key?(state.states, "map-editor.LAYERS.1")
    end

    test "feature_impl_state entry has correct status values" do
      product = get_product!("mapperoni", "site")
      spec = get_spec!(product, "map-editor")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "production")

      state =
        Repo.get_by(FeatureImplState, feature_name: spec.feature_name, implementation_id: impl.id)

      canvas_state = state.states["map-editor.CANVAS.1"]

      # data-model.FEATURE_IMPL_STATES.4-3: Valid status values
      assert canvas_state["status"] in [
               "pending",
               "in_progress",
               "blocked",
               "completed",
               "rejected"
             ]

      assert canvas_state["updated_at"] != nil
    end

    test "idempotent: running seeds twice doesn't duplicate feature_impl_states" do
      state_count_before = Repo.aggregate(FeatureImplState, :count)
      Acai.Seeds.run(silent: true)
      state_count_after = Repo.aggregate(FeatureImplState, :count)
      assert state_count_before == state_count_after
    end
  end

  # data-model.FEATURE_BRANCH_REFS
  describe "feature_branch_ref seeding" do
    test "creates feature_branch_ref for map-editor spec on site_main branch" do
      team = Repo.get_by!(Acai.Teams.Team, name: "mapperoni")

      branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/mapperoni-site"
        )

      ref =
        Repo.get_by(FeatureBranchRef, feature_name: "map-editor", branch_id: branch.id)

      assert ref != nil
    end

    test "feature_branch_ref has JSONB refs keyed by ACID" do
      team = Repo.get_by!(Acai.Teams.Team, name: "mapperoni")

      branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/mapperoni-site"
        )

      ref =
        Repo.get_by(FeatureBranchRef, feature_name: "map-editor", branch_id: branch.id)

      # data-model.FEATURE_BRANCH_REFS.4: Refs keyed by ACID
      assert is_map(ref.refs)
      assert Map.has_key?(ref.refs, "map-editor.CANVAS.1")
    end

    test "feature_branch_ref entry has correct reference structure" do
      team = Repo.get_by!(Acai.Teams.Team, name: "mapperoni")

      branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/mapperoni-site"
        )

      ref =
        Repo.get_by(FeatureBranchRef, feature_name: "map-editor", branch_id: branch.id)

      canvas_refs = ref.refs["map-editor.CANVAS.1"]

      # data-model.FEATURE_BRANCH_REFS.4-3: Each reference has path, is_test (no repo/loc)
      assert is_list(canvas_refs)
      first_ref = List.first(canvas_refs)
      assert first_ref["path"] != nil
      assert is_boolean(first_ref["is_test"])
    end

    test "feature_branch_ref has commit and pushed_at" do
      team = Repo.get_by!(Acai.Teams.Team, name: "mapperoni")

      branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/mapperoni-site"
        )

      ref =
        Repo.get_by(FeatureBranchRef, feature_name: "map-editor", branch_id: branch.id)

      # data-model.FEATURE_BRANCH_REFS.6,7
      assert ref.commit != nil
      assert ref.pushed_at != nil
    end

    test "idempotent: running seeds twice doesn't duplicate feature_branch_refs" do
      ref_count_before = Repo.aggregate(FeatureBranchRef, :count)
      Acai.Seeds.run(silent: true)
      ref_count_after = Repo.aggregate(FeatureBranchRef, :count)
      assert ref_count_before == ref_count_after
    end
  end
end
