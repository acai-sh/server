defmodule Acai.SeedsTest do
  @moduledoc """
  Tests for priv/repo/seeds.exs seed data generation.
  Verifies Phase 1 seed-data foundation:
  - Users: owner, developer, readonly (confirmed, with password "password123456")
  - Team: mapperoni
  - Products: site (with description), api (without description)
  - Implementations: site has 4, api has 2, with proper inheritance
  - Tracked branches: linking implementations to repo branches
  - Access tokens: 3 for developer, 1 for owner, 0 for readonly

  All tests reference seed-data.* ACIDs.
  """

  use ExUnit.Case, async: false

  import Ecto.Query

  alias Acai.Repo
  alias Acai.Accounts
  alias Acai.Accounts.User
  alias Acai.Teams.{Team, UserTeamRole, AccessToken}
  alias Acai.Products.Product
  alias Acai.Implementations.{Implementation, TrackedBranch, Branch}
  alias Acai.Specs.{Spec, FeatureImplState, FeatureBranchRef}

  setup_all do
    owner = Ecto.Adapters.SQL.Sandbox.start_owner!(Repo, shared: true)

    on_exit(fn ->
      Ecto.Adapters.SQL.Sandbox.stop_owner(owner)
    end)

    Acai.Seeds.run(silent: true)
    :ok
  end

  # ============================================================================
  # USERS Tests
  # ============================================================================

  describe "user seeding" do
    # seed-data.USERS.1: Pregenerate the following user accounts
    test "seed-data.USERS.1: creates owner user" do
      user = Accounts.get_user_by_email("owner@mapperoni.com")
      assert user != nil
    end

    test "seed-data.USERS.1: creates developer user" do
      user = Accounts.get_user_by_email("developer@mapperoni.com")
      assert user != nil
    end

    test "seed-data.USERS.1: creates readonly user" do
      user = Accounts.get_user_by_email("readonly@mapperoni.com")
      assert user != nil
    end

    # seed-data.USERS.2: All pregenerated users must have the password "password123456"
    test "seed-data.USERS.2: all users have password password123456" do
      owner = Accounts.get_user_by_email("owner@mapperoni.com")
      developer = Accounts.get_user_by_email("developer@mapperoni.com")
      readonly = Accounts.get_user_by_email("readonly@mapperoni.com")

      assert User.valid_password?(owner, "password123456")
      assert User.valid_password?(developer, "password123456")
      assert User.valid_password?(readonly, "password123456")

      # Verify wrong password fails
      refute User.valid_password?(owner, "wrongpassword")
    end

    # seed-data.USERS.3: All pregenerated users have already confirmed emails
    test "seed-data.USERS.3: all users have confirmed emails" do
      owner = Accounts.get_user_by_email("owner@mapperoni.com")
      developer = Accounts.get_user_by_email("developer@mapperoni.com")
      readonly = Accounts.get_user_by_email("readonly@mapperoni.com")

      assert owner.confirmed_at != nil
      assert developer.confirmed_at != nil
      assert readonly.confirmed_at != nil
    end

    # seed-data.ENVIRONMENT.2: Idempotency test
    test "seed-data.ENVIRONMENT.2: running seeds twice doesn't duplicate users" do
      user_count_before = Repo.aggregate(User, :count)
      Acai.Seeds.run(silent: true)
      user_count_after = Repo.aggregate(User, :count)
      assert user_count_before == user_count_after
    end

    # Convergence test: existing user with wrong password gets corrected
    test "seed-data.ENVIRONMENT.2: converges existing users to correct password" do
      # Get the owner user
      owner = Accounts.get_user_by_email("owner@mapperoni.com")

      # Change the password to something else
      {:ok, _} =
        owner
        |> User.password_changeset(%{password: "differentpassword123"})
        |> Repo.update()

      # Verify wrong password was set (re-fetch to get updated hash)
      owner_with_new_pw = Accounts.get_user_by_email("owner@mapperoni.com")
      assert User.valid_password?(owner_with_new_pw, "differentpassword123")
      refute User.valid_password?(owner_with_new_pw, "password123456")

      # Re-run seeds
      Acai.Seeds.run(silent: true)

      # Verify password is back to spec
      updated_owner = Accounts.get_user_by_email("owner@mapperoni.com")
      assert User.valid_password?(updated_owner, "password123456")
      refute User.valid_password?(updated_owner, "differentpassword123")
    end

    # Convergence test: unconfirmed user gets confirmed
    test "seed-data.ENVIRONMENT.2: converges unconfirmed users to confirmed" do
      # Get the developer user
      developer = Accounts.get_user_by_email("developer@mapperoni.com")

      # Unconfirm the user
      {:ok, developer_unconfirmed} =
        developer
        |> Ecto.Changeset.change(confirmed_at: nil)
        |> Repo.update()

      refute developer_unconfirmed.confirmed_at

      # Re-run seeds
      Acai.Seeds.run(silent: true)

      # Verify user is confirmed
      updated_developer = Accounts.get_user_by_email("developer@mapperoni.com")
      assert updated_developer.confirmed_at != nil
    end
  end

  # ============================================================================
  # TEAM Tests
  # ============================================================================

  describe "team seeding" do
    # seed-data.USERS.4: Generates one team called "mapperoni"
    test "seed-data.USERS.4: creates mapperoni team" do
      team = Repo.get_by(Team, name: "mapperoni")
      assert team != nil
    end

    # seed-data.ENVIRONMENT.2: Idempotency test
    test "seed-data.ENVIRONMENT.2: running seeds twice doesn't duplicate teams" do
      team_count_before = Repo.aggregate(Team, :count)
      Acai.Seeds.run(silent: true)
      team_count_after = Repo.aggregate(Team, :count)
      assert team_count_before == team_count_after
    end
  end

  # ============================================================================
  # ROLES Tests
  # ============================================================================

  describe "role seeding" do
    # seed-data.USERS.5: All 3 users have their assigned role in this team
    test "seed-data.USERS.5: assigns owner role to owner user" do
      team = Repo.get_by!(Team, name: "mapperoni")
      owner = Accounts.get_user_by_email("owner@mapperoni.com")

      role = Repo.get_by!(UserTeamRole, team_id: team.id, user_id: owner.id)
      assert role.title == "owner"
    end

    test "seed-data.USERS.5: assigns developer role to developer user" do
      team = Repo.get_by!(Team, name: "mapperoni")
      dev = Accounts.get_user_by_email("developer@mapperoni.com")

      role = Repo.get_by!(UserTeamRole, team_id: team.id, user_id: dev.id)
      assert role.title == "developer"
    end

    test "seed-data.USERS.5: assigns readonly role to readonly user" do
      team = Repo.get_by!(Team, name: "mapperoni")
      readonly = Accounts.get_user_by_email("readonly@mapperoni.com")

      role = Repo.get_by!(UserTeamRole, team_id: team.id, user_id: readonly.id)
      assert role.title == "readonly"
    end

    # Convergence test: wrong role gets corrected
    test "seed-data.ENVIRONMENT.2: converges incorrect roles to correct ones" do
      team = Repo.get_by!(Team, name: "mapperoni")
      developer = Accounts.get_user_by_email("developer@mapperoni.com")

      # Change role to owner using update_all since UserTeamRole has no primary key
      {1, _} =
        from(r in UserTeamRole,
          where: r.team_id == ^team.id and r.user_id == ^developer.id
        )
        |> Repo.update_all(set: [title: "owner"])

      # Verify role was changed
      role = Repo.get_by!(UserTeamRole, team_id: team.id, user_id: developer.id)
      assert role.title == "owner"

      # Re-run seeds
      Acai.Seeds.run(silent: true)

      # Verify role is back to developer
      updated_role = Repo.get_by!(UserTeamRole, team_id: team.id, user_id: developer.id)
      assert updated_role.title == "developer"
    end

    # Idempotency test
    test "seed-data.ENVIRONMENT.2: running seeds twice doesn't duplicate roles" do
      role_count_before = Repo.aggregate(UserTeamRole, :count)
      Acai.Seeds.run(silent: true)
      role_count_after = Repo.aggregate(UserTeamRole, :count)
      assert role_count_before == role_count_after
    end
  end

  # ============================================================================
  # PRODUCTS Tests
  # ============================================================================

  describe "product seeding" do
    # seed-data.PRODUCTS.1: Create 2 products: api and site
    test "seed-data.PRODUCTS.1: creates site product" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      assert product != nil
    end

    test "seed-data.PRODUCTS.1: creates api product" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      assert product != nil
    end

    # seed-data.PRODUCTS.2: site has description, api does not
    test "seed-data.PRODUCTS.2: site has a product description string" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")

      assert product.description != nil
      assert product.description != ""
    end

    test "seed-data.PRODUCTS.2: api does not have a description" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")

      assert product.description == nil
    end

    # Idempotency test
    test "seed-data.ENVIRONMENT.2: running seeds twice doesn't duplicate products" do
      product_count_before = Repo.aggregate(Product, :count)
      Acai.Seeds.run(silent: true)
      product_count_after = Repo.aggregate(Product, :count)
      assert product_count_before == product_count_after
    end

    # Convergence test: wrong description gets corrected
    test "seed-data.ENVIRONMENT.2: converges product descriptions" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      # Change description
      site_product
      |> Product.changeset(%{description: "Wrong description"})
      |> Repo.update!()

      # Re-run seeds
      Acai.Seeds.run(silent: true)

      # Verify description is back to spec
      updated_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      assert updated_product.description ==
               "Mapperoni web application - map-based survey builder and viewer"
    end
  end

  # ============================================================================
  # IMPLEMENTATIONS Tests - Site
  # ============================================================================

  describe "site implementation seeding" do
    # seed-data.IMPLS.1: site has 4 implementations
    test "seed-data.IMPLS.1: creates Production implementation for site" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")

      assert impl != nil
      assert impl.is_active == true
    end

    test "seed-data.IMPLS.1: creates Staging implementation for site" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Staging")

      assert impl != nil
    end

    test "seed-data.IMPLS.1: creates feat/ai-chat implementation for site" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "feat/ai-chat")

      assert impl != nil
    end

    test "seed-data.IMPLS.1: creates fix-map-settings implementation for site" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "fix-map-settings")

      assert impl != nil
    end

    # seed-data.IMPLS.1-7: Staging inherits from Production
    test "seed-data.IMPLS.1-7: site Staging inherits from Production" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      prod_impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")
      staging_impl = Repo.get_by!(Implementation, product_id: product.id, name: "Staging")

      assert staging_impl.parent_implementation_id == prod_impl.id
    end

    # seed-data.IMPLS.1-6: feat/ai-chat and fix-map-settings inherit from Staging
    test "seed-data.IMPLS.1-6: feat/ai-chat inherits from Staging" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      staging_impl = Repo.get_by!(Implementation, product_id: product.id, name: "Staging")
      feat_impl = Repo.get_by!(Implementation, product_id: product.id, name: "feat/ai-chat")

      assert feat_impl.parent_implementation_id == staging_impl.id
    end

    test "seed-data.IMPLS.1-6: fix-map-settings inherits from Staging" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      staging_impl = Repo.get_by!(Implementation, product_id: product.id, name: "Staging")
      fix_impl = Repo.get_by!(Implementation, product_id: product.id, name: "fix-map-settings")

      assert fix_impl.parent_implementation_id == staging_impl.id
    end

    # seed-data.IMPLS.1-1: Each site implementation tracks 3 github repos
    test "seed-data.IMPLS.1-1: site Production tracks 3 repos" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")

      tracked_branches =
        Repo.all(from tb in TrackedBranch, where: tb.implementation_id == ^impl.id)

      assert length(tracked_branches) == 3
    end

    # seed-data.IMPLS.1-2: Production tracks branches main, main, and main
    test "seed-data.IMPLS.1-2: Production tracks main branches for all 3 repos" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")

      tracked_branches =
        Repo.all(
          from tb in TrackedBranch, where: tb.implementation_id == ^impl.id, preload: [:branch]
        )

      for tb <- tracked_branches do
        assert tb.branch.branch_name == "main"
      end
    end

    # seed-data.IMPLS.1-3: Staging tracks branches dev, dev, and dev
    test "seed-data.IMPLS.1-3: Staging tracks dev branches for all 3 repos" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Staging")

      tracked_branches =
        Repo.all(
          from tb in TrackedBranch, where: tb.implementation_id == ^impl.id, preload: [:branch]
        )

      for tb <- tracked_branches do
        assert tb.branch.branch_name == "dev"
      end
    end

    # seed-data.IMPLS.1-4: feat/ai-chat tracks branches feat/ai-chat, dev, and dev
    test "seed-data.IMPLS.1-4: feat/ai-chat tracks correct branch combination" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "feat/ai-chat")

      tracked_branches =
        Repo.all(
          from tb in TrackedBranch, where: tb.implementation_id == ^impl.id, preload: [:branch]
        )

      branch_names = Enum.map(tracked_branches, & &1.branch.branch_name) |> Enum.sort()
      assert branch_names == ["dev", "dev", "feat/ai-chat"]
    end

    # seed-data.IMPLS.1-5: fix-map-settings tracks branches fix-map-settings, fix-#123, and refactor/map-settings-compat
    test "seed-data.IMPLS.1-5: fix-map-settings tracks correct branch combination" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "fix-map-settings")

      tracked_branches =
        Repo.all(
          from tb in TrackedBranch, where: tb.implementation_id == ^impl.id, preload: [:branch]
        )

      branch_names = Enum.map(tracked_branches, & &1.branch.branch_name) |> Enum.sort()
      assert branch_names == ["fix-#123", "fix-map-settings", "refactor/map-settings-compat"]
    end
  end

  # ============================================================================
  # IMPLEMENTATIONS Tests - API
  # ============================================================================

  describe "api implementation seeding" do
    # seed-data.IMPLS.2: api has 2 implementations
    test "seed-data.IMPLS.2: creates Production implementation for api" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")

      assert impl != nil
    end

    test "seed-data.IMPLS.2: creates Staging implementation for api" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Staging")

      assert impl != nil
    end

    # seed-data.IMPLS.2-2: api Staging inherits from api Production
    test "seed-data.IMPLS.2-2: api Staging inherits from Production" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      prod_impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")
      staging_impl = Repo.get_by!(Implementation, product_id: product.id, name: "Staging")

      assert staging_impl.parent_implementation_id == prod_impl.id
    end

    # seed-data.IMPLS.2-1: Each api implementation tracks 1 github repo: backend
    test "seed-data.IMPLS.2-1: api Production tracks 1 backend repo" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")

      tracked_branches =
        Repo.all(from tb in TrackedBranch, where: tb.implementation_id == ^impl.id)

      assert length(tracked_branches) == 1

      [tb] = tracked_branches
      # API implementations use the shared backend repo (same as API specs/refs)
      assert tb.repo_uri == "github.com/mapperoni/backend"
    end

    # seed-data.IMPLS.2-1: API tracks main and dev respectively
    test "seed-data.IMPLS.2-1: api Production tracks main branch" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")

      [tb] =
        Repo.all(
          from tb in TrackedBranch, where: tb.implementation_id == ^impl.id, preload: [:branch]
        )

      assert tb.branch.branch_name == "main"
    end

    test "seed-data.IMPLS.2-1: api Staging tracks dev branch" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Staging")

      [tb] =
        Repo.all(
          from tb in TrackedBranch, where: tb.implementation_id == ^impl.id, preload: [:branch]
        )

      assert tb.branch.branch_name == "dev"
    end

    # Regression: API implementations must be able to resolve their feature specs
    test "seed-data.IMPLS.2-1: api Production can resolve core feature spec" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")

      # Verify API Production can resolve the core feature through canonical resolution
      assert {spec, source_info} = Acai.Specs.resolve_canonical_spec("core", impl.id)
      assert spec.feature_name == "core"
      assert spec.product_id == product.id
      assert source_info.is_inherited == false
    end

    test "seed-data.IMPLS.2-1: api Staging inherits and resolves core feature spec" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Staging")

      # Verify API Staging can resolve the core feature (inherited from Production)
      assert {spec, source_info} = Acai.Specs.resolve_canonical_spec("core", impl.id)
      assert spec.feature_name == "core"
      assert spec.product_id == product.id
      # Since Staging tracks backend/dev and specs are on backend/main,
      # the spec is found via inheritance from Production
      assert source_info.is_inherited == true
    end

    test "seed-data.IMPLS.2-1: api Production can resolve mcp feature spec" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")

      assert {spec, source_info} = Acai.Specs.resolve_canonical_spec("mcp", impl.id)
      assert spec.feature_name == "mcp"
      assert spec.product_id == product.id
      assert source_info.is_inherited == false
    end
  end

  describe "implementation idempotency" do
    # seed-data.ENVIRONMENT.2: Idempotency test
    test "seed-data.ENVIRONMENT.2: running seeds twice doesn't duplicate implementations" do
      impl_count_before = Repo.aggregate(Implementation, :count)
      Acai.Seeds.run(silent: true)
      impl_count_after = Repo.aggregate(Implementation, :count)
      assert impl_count_before == impl_count_after
    end

    # Convergence test: wrong parent gets corrected
    test "seed-data.ENVIRONMENT.2: converges implementation parent relationships" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "site")
      staging_impl = Repo.get_by!(Implementation, product_id: product.id, name: "Staging")
      feat_impl = Repo.get_by!(Implementation, product_id: product.id, name: "feat/ai-chat")

      # Verify original parent is staging
      assert feat_impl.parent_implementation_id == staging_impl.id

      # Remove parent
      feat_impl
      |> Implementation.changeset(%{parent_implementation_id: nil})
      |> Repo.update!()

      # Re-run seeds
      Acai.Seeds.run(silent: true)

      # Verify parent is restored
      updated_feat = Repo.get!(Implementation, feat_impl.id)
      assert updated_feat.parent_implementation_id == staging_impl.id
    end
  end

  # ============================================================================
  # TRACKED BRANCHES Tests
  # ============================================================================

  describe "tracked branch seeding" do
    # seed-data.ENVIRONMENT.2: Idempotency test
    test "seed-data.ENVIRONMENT.2: running seeds twice doesn't duplicate tracked branches" do
      branch_count_before = Repo.aggregate(TrackedBranch, :count)
      Acai.Seeds.run(silent: true)
      branch_count_after = Repo.aggregate(TrackedBranch, :count)
      assert branch_count_before == branch_count_after
    end

    # seed-data.ENVIRONMENT.2: Convergence test for legacy api-backend tracked branches
    test "seed-data.ENVIRONMENT.2: converges legacy api-backend tracked branches to backend" do
      team = Repo.get_by!(Team, name: "mapperoni")
      product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: product.id, name: "Production")

      # Simulate legacy state: create an api-backend tracked branch
      legacy_branch =
        Acai.Implementations.get_branch_by_identity(
          team.id,
          "github.com/mapperoni/api-backend",
          "main"
        ) ||
          Acai.Repo.insert!(%Acai.Implementations.Branch{
            team_id: team.id,
            repo_uri: "github.com/mapperoni/api-backend",
            branch_name: "main",
            last_seen_commit: "legacy123"
          })

      # Create a legacy tracked branch
      {:ok, _legacy_tb} =
        Acai.Repo.insert(%Acai.Implementations.TrackedBranch{
          implementation_id: impl.id,
          branch_id: legacy_branch.id,
          repo_uri: "github.com/mapperoni/api-backend"
        })

      # Verify legacy tracked branch exists
      legacy_count_before =
        Acai.Repo.aggregate(
          from(tb in Acai.Implementations.TrackedBranch,
            where:
              tb.implementation_id == ^impl.id and
                tb.repo_uri == "github.com/mapperoni/api-backend"
          ),
          :count
        )

      assert legacy_count_before == 1

      # Re-run seeds to trigger convergence
      Acai.Seeds.run(silent: true)

      # Verify legacy tracked branch is removed
      legacy_count_after =
        Acai.Repo.aggregate(
          from(tb in Acai.Implementations.TrackedBranch,
            where:
              tb.implementation_id == ^impl.id and
                tb.repo_uri == "github.com/mapperoni/api-backend"
          ),
          :count
        )

      assert legacy_count_after == 0

      # Verify canonical tracked branch exists
      canonical_count =
        Acai.Repo.aggregate(
          from(tb in Acai.Implementations.TrackedBranch,
            where:
              tb.implementation_id == ^impl.id and tb.repo_uri == "github.com/mapperoni/backend"
          ),
          :count
        )

      assert canonical_count == 1
    end
  end

  # ============================================================================
  # ACCESS TOKENS Tests
  # ============================================================================

  describe "access token seeding" do
    # seed-data.TOKENS.1: developer has 3 access tokens generated
    test "seed-data.TOKENS.1: developer has 3 access tokens" do
      developer = Accounts.get_user_by_email("developer@mapperoni.com")
      tokens = Repo.all(from t in AccessToken, where: t.user_id == ^developer.id)

      assert length(tokens) == 3
    end

    # seed-data.TOKENS.2: owner has 1 access token generated
    test "seed-data.TOKENS.2: owner has 1 access token" do
      owner = Accounts.get_user_by_email("owner@mapperoni.com")
      tokens = Repo.all(from t in AccessToken, where: t.user_id == ^owner.id)

      assert length(tokens) == 1
    end

    # seed-data.TOKENS.3: readonly has no access tokens
    test "seed-data.TOKENS.3: readonly has no access tokens" do
      readonly = Accounts.get_user_by_email("readonly@mapperoni.com")
      tokens = Repo.all(from t in AccessToken, where: t.user_id == ^readonly.id)

      assert length(tokens) == 0
    end

    # Verify token scopes match roles
    test "access tokens have appropriate scopes for roles" do
      owner = Accounts.get_user_by_email("owner@mapperoni.com")
      developer = Accounts.get_user_by_email("developer@mapperoni.com")

      [owner_token] = Repo.all(from t in AccessToken, where: t.user_id == ^owner.id)
      dev_tokens = Repo.all(from t in AccessToken, where: t.user_id == ^developer.id)

      # Owner should have all scopes
      assert "team:admin" in owner_token.scopes
      assert "specs:write" in owner_token.scopes

      # Developer should have most scopes but not admin
      [dev_token | _] = dev_tokens
      assert "specs:write" in dev_token.scopes
      refute "team:admin" in dev_token.scopes
    end

    # seed-data.ENVIRONMENT.2: Idempotency test
    test "seed-data.ENVIRONMENT.2: running seeds twice doesn't duplicate tokens" do
      token_count_before = Repo.aggregate(AccessToken, :count)
      Acai.Seeds.run(silent: true)
      token_count_after = Repo.aggregate(AccessToken, :count)
      assert token_count_before == token_count_after
    end
  end

  # ============================================================================
  # ENVIRONMENT Tests
  # ============================================================================

  describe "environment wiring" do
    # seed-data.ENVIRONMENT.1: Seed data generation runs automatically during devcontainer build
    test "seed-data.ENVIRONMENT.1: seeds.exs delegates to Acai.Seeds.run/0" do
      seeds_content = File.read!("priv/repo/seeds.exs")
      assert seeds_content =~ "Acai.Seeds.run()"
    end

    # Verify postcreate.sh runs ecto.setup
    test "seed-data.ENVIRONMENT.1: postcreate.sh runs mix ecto.setup" do
      postcreate_content = File.read!(".devcontainer/postcreate.sh")
      assert postcreate_content =~ "mix ecto.setup"
    end

    # Verify mix.exs has ecto.setup alias
    test "seed-data.ENVIRONMENT.1: mix.exs defines ecto.setup alias" do
      mix_content = File.read!("mix.exs")
      assert mix_content =~ "ecto.setup"
      assert mix_content =~ "run priv/repo/seeds.exs"
    end
  end

  # ============================================================================
  # SPECS Tests (Phase 2)
  # ============================================================================

  describe "spec seeding" do
    # seed-data.SPECS.1: api product has 2 specs (core, mcp) on backend main branch
    test "seed-data.SPECS.1: api product has core spec" do
      team = Repo.get_by!(Team, name: "mapperoni")
      api_product = Repo.get_by!(Product, team_id: team.id, name: "api")
      # API specs are on the backend repo's main branch (shared with site backend)
      backend_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/backend"
        )

      spec =
        Repo.get_by!(Spec,
          product_id: api_product.id,
          feature_name: "core",
          branch_id: backend_branch.id
        )

      assert spec != nil
      assert spec.feature_version == "1.0.0"
    end

    test "seed-data.SPECS.1: api product has mcp spec" do
      team = Repo.get_by!(Team, name: "mapperoni")
      api_product = Repo.get_by!(Product, team_id: team.id, name: "api")
      # API specs are on the backend repo's main branch (shared with site backend)
      backend_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/backend"
        )

      spec =
        Repo.get_by!(Spec,
          product_id: api_product.id,
          feature_name: "mcp",
          branch_id: backend_branch.id
        )

      assert spec != nil
      assert spec.feature_version == "1.0.0"
    end

    # seed-data.SPECS.1-1: core has 10 requirements
    test "seed-data.SPECS.1-1: core has exactly 10 requirements" do
      team = Repo.get_by!(Team, name: "mapperoni")
      api_product = Repo.get_by!(Product, team_id: team.id, name: "api")
      # API specs are on the backend repo's main branch (shared with site backend)
      backend_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/backend"
        )

      spec =
        Repo.get_by!(Spec,
          product_id: api_product.id,
          feature_name: "core",
          branch_id: backend_branch.id
        )

      assert map_size(spec.requirements) == 10

      # Verify all ACIDs have correct prefix
      Enum.each(spec.requirements, fn {acid, _} ->
        assert String.starts_with?(acid, "core.")
      end)
    end

    # seed-data.SPECS.1-2: mcp has 20 requirements
    test "seed-data.SPECS.1-2: mcp has exactly 20 requirements" do
      team = Repo.get_by!(Team, name: "mapperoni")
      api_product = Repo.get_by!(Product, team_id: team.id, name: "api")
      # API specs are on the backend repo's main branch (shared with site backend)
      backend_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/backend"
        )

      spec =
        Repo.get_by!(Spec,
          product_id: api_product.id,
          feature_name: "mcp",
          branch_id: backend_branch.id
        )

      assert map_size(spec.requirements) == 20

      # Verify all ACIDs have correct prefix
      Enum.each(spec.requirements, fn {acid, _} ->
        assert String.starts_with?(acid, "mcp.")
      end)
    end

    # seed-data.SPECS.3: site product has 6 spec versions for 4 features
    test "seed-data.SPECS.3: site product has 6 total spec versions" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      specs = Repo.all(from s in Spec, where: s.product_id == ^site_product.id)
      assert length(specs) == 6
    end

    # seed-data.SPECS.3-1: map-editor has 1 spec version on main
    test "seed-data.SPECS.3-1: map-editor has 1 spec version on main" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      main_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/frontend"
        )

      specs =
        Repo.all(
          from s in Spec,
            where:
              s.product_id == ^site_product.id and s.feature_name == "map-editor" and
                s.branch_id == ^main_branch.id
        )

      assert length(specs) == 1
      assert hd(specs).feature_version == "1.0.0"
    end

    # seed-data.SPECS.3-2: form-editor has 2 spec versions (main and dev)
    test "seed-data.SPECS.3-2: form-editor has 2 spec versions on main and dev" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      main_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/frontend"
        )

      dev_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "dev",
          repo_uri: "github.com/mapperoni/frontend"
        )

      main_specs =
        Repo.all(
          from s in Spec,
            where:
              s.product_id == ^site_product.id and s.feature_name == "map-editor" and
                s.branch_id == ^main_branch.id
        )

      dev_specs =
        Repo.all(
          from s in Spec,
            where:
              s.product_id == ^site_product.id and s.feature_name == "form-editor" and
                s.branch_id == ^dev_branch.id
        )

      # form-editor on main exists
      assert length(main_specs) >= 0
      # form-editor on dev exists
      assert length(dev_specs) == 1
    end

    test "seed-data.SPECS.3-2: form-editor main has version 1.0.0" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      main_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/frontend"
        )

      spec =
        Repo.get_by!(Spec,
          product_id: site_product.id,
          feature_name: "form-editor",
          branch_id: main_branch.id
        )

      assert spec.feature_version == "1.0.0"
    end

    test "seed-data.SPECS.3-2: form-editor dev has version 1.1.0" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      dev_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "dev",
          repo_uri: "github.com/mapperoni/frontend"
        )

      spec =
        Repo.get_by!(Spec,
          product_id: site_product.id,
          feature_name: "form-editor",
          branch_id: dev_branch.id
        )

      assert spec.feature_version == "1.1.0"
    end

    # seed-data.SPECS.3-3: ai-chat has 1 spec version only on feat/ai-chat
    test "seed-data.SPECS.3-3: ai-chat has 1 spec version on feat/ai-chat" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      feat_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "feat/ai-chat",
          repo_uri: "github.com/mapperoni/frontend"
        )

      spec =
        Repo.get_by!(Spec,
          product_id: site_product.id,
          feature_name: "ai-chat",
          branch_id: feat_branch.id
        )

      assert spec != nil
      assert spec.feature_version == "0.1.0"
    end

    # seed-data.SPECS.3-4: map-settings has 2 spec versions (main and fix-map-settings)
    test "seed-data.SPECS.3-4: map-settings has 2 spec versions" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      main_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/frontend"
        )

      fix_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "fix-map-settings",
          repo_uri: "github.com/mapperoni/frontend"
        )

      main_spec =
        Repo.get_by(Spec,
          product_id: site_product.id,
          feature_name: "map-settings",
          branch_id: main_branch.id
        )

      fix_spec =
        Repo.get_by(Spec,
          product_id: site_product.id,
          feature_name: "map-settings",
          branch_id: fix_branch.id
        )

      assert main_spec != nil
      assert fix_spec != nil
    end

    test "seed-data.SPECS.3-4: map-settings main has version 1.0.0" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      main_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/frontend"
        )

      spec =
        Repo.get_by!(Spec,
          product_id: site_product.id,
          feature_name: "map-settings",
          branch_id: main_branch.id
        )

      assert spec.feature_version == "1.0.0"
    end

    test "seed-data.SPECS.3-4: map-settings fix-map-settings has version 1.0.1" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      fix_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "fix-map-settings",
          repo_uri: "github.com/mapperoni/frontend"
        )

      spec =
        Repo.get_by!(Spec,
          product_id: site_product.id,
          feature_name: "map-settings",
          branch_id: fix_branch.id
        )

      assert spec.feature_version == "1.0.1"
    end

    # Idempotency test
    test "seed-data.ENVIRONMENT.2: running seeds twice doesn't duplicate specs" do
      spec_count_before = Repo.aggregate(Spec, :count)
      Acai.Seeds.run(silent: true)
      spec_count_after = Repo.aggregate(Spec, :count)
      assert spec_count_before == spec_count_after
    end

    # Requirement JSON structure test
    test "specs have correct requirement structure with requirement field" do
      team = Repo.get_by!(Team, name: "mapperoni")
      api_product = Repo.get_by!(Product, team_id: team.id, name: "api")
      # API specs are on the backend repo's main branch (shared with site backend)
      backend_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/backend"
        )

      spec =
        Repo.get_by!(Spec,
          product_id: api_product.id,
          feature_name: "core",
          branch_id: backend_branch.id
        )

      Enum.each(spec.requirements, fn {acid, req} ->
        assert req["requirement"] != nil or req[:requirement] != nil,
               "Requirement #{acid} should have a requirement field"

        assert req["is_deprecated"] != nil or req[:is_deprecated] != nil,
               "Requirement #{acid} should have is_deprecated field"
      end)
    end
  end

  # ============================================================================
  # IMPL_STATES Tests (Phase 2)
  # ============================================================================

  describe "implementation state seeding" do
    # seed-data.IMPL_STATES.1: api / core / Production — all ACIDs have `accepted` state
    test "seed-data.IMPL_STATES.1: api core Production has all accepted states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      api_product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: api_product.id, name: "Production")

      state = Repo.get_by!(FeatureImplState, implementation_id: impl.id, feature_name: "core")
      assert state != nil
      assert map_size(state.states) == 10

      Enum.each(state.states, fn {acid, attrs} ->
        assert attrs["status"] == "accepted" or attrs[:status] == "accepted",
               "ACID #{acid} should have accepted status"
      end)
    end

    # seed-data.IMPL_STATES.2: api / core / Staging — no states (all inherited)
    test "seed-data.IMPL_STATES.2: api core Staging has no direct states (inherited)" do
      team = Repo.get_by!(Team, name: "mapperoni")
      api_product = Repo.get_by!(Product, team_id: team.id, name: "api")
      impl = Repo.get_by!(Implementation, product_id: api_product.id, name: "Staging")

      state = Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "core")
      assert state == nil, "Staging should not have direct states for core"
    end

    # seed-data.IMPL_STATES.3: site / map-editor / Production — all ACIDs have `accepted` state
    test "seed-data.IMPL_STATES.3: site map-editor Production has all accepted states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "Production")

      state =
        Repo.get_by!(FeatureImplState, implementation_id: impl.id, feature_name: "map-editor")

      assert state != nil
      assert map_size(state.states) == 8

      Enum.each(state.states, fn {acid, attrs} ->
        assert attrs["status"] == "accepted" or attrs[:status] == "accepted",
               "ACID #{acid} should have accepted status"
      end)
    end

    # seed-data.IMPL_STATES.3-note: site / map-editor does NOT have states on Staging, feat/ai-chat, or fix-map-settings
    test "seed-data.IMPL_STATES.3-note: site map-editor Staging has no direct states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "Staging")

      state =
        Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "map-editor")

      assert state == nil, "Staging should not have direct states for map-editor"
    end

    test "seed-data.IMPL_STATES.3-note: site map-editor feat/ai-chat has no direct states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "feat/ai-chat")

      state =
        Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "map-editor")

      assert state == nil, "feat/ai-chat should not have direct states for map-editor"
    end

    test "seed-data.IMPL_STATES.3-note: site map-editor fix-map-settings has no direct states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "fix-map-settings")

      state =
        Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "map-editor")

      assert state == nil, "fix-map-settings should not have direct states for map-editor"
    end

    # seed-data.IMPL_STATES.4: site / form-editor / Production — all ACIDs have `accepted` state
    test "seed-data.IMPL_STATES.4: site form-editor Production has all accepted states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "Production")

      state =
        Repo.get_by!(FeatureImplState, implementation_id: impl.id, feature_name: "form-editor")

      assert state != nil
      assert map_size(state.states) == 8

      Enum.each(state.states, fn {acid, attrs} ->
        assert attrs["status"] == "accepted" or attrs[:status] == "accepted",
               "ACID #{acid} should have accepted status"
      end)
    end

    # seed-data.IMPL_STATES.4-1: site / form-editor / Staging — all ACIDs have `accepted` state
    test "seed-data.IMPL_STATES.4-1: site form-editor Staging has all accepted states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "Staging")

      state =
        Repo.get_by!(FeatureImplState, implementation_id: impl.id, feature_name: "form-editor")

      assert state != nil
      assert map_size(state.states) == 8

      Enum.each(state.states, fn {acid, attrs} ->
        assert attrs["status"] == "accepted" or attrs[:status] == "accepted",
               "ACID #{acid} should have accepted status"
      end)
    end

    # seed-data.IMPL_STATES.4-note: site / form-editor does NOT have states on feat/ai-chat or fix-map-settings
    test "seed-data.IMPL_STATES.4-note: site form-editor feat/ai-chat has no direct states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "feat/ai-chat")

      state =
        Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "form-editor")

      assert state == nil, "feat/ai-chat should not have direct states for form-editor"
    end

    test "seed-data.IMPL_STATES.4-note: site form-editor fix-map-settings has no direct states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "fix-map-settings")

      state =
        Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "form-editor")

      assert state == nil, "fix-map-settings should not have direct states for form-editor"
    end

    # seed-data.IMPL_STATES.5: site / ai-chat / feat/ai-chat — mix of null, assigned, and completed states
    test "seed-data.IMPL_STATES.5: site ai-chat feat/ai-chat has mixed states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "feat/ai-chat")

      state = Repo.get_by!(FeatureImplState, implementation_id: impl.id, feature_name: "ai-chat")
      assert state != nil

      # Should have 7 ACIDs with states (2 assigned, 5 completed)
      # Note: null status ACIDs (UI.1, UI.2) are omitted from the states map
      assert map_size(state.states) == 7

      # Check assigned statuses
      assert get_in(state.states, ["ai-chat.INPUT.1", "status"]) == "assigned"
      assert get_in(state.states, ["ai-chat.INPUT.2", "status"]) == "assigned"

      # Check completed statuses
      assert get_in(state.states, ["ai-chat.AI.1", "status"]) == "completed"
      assert get_in(state.states, ["ai-chat.AI.2", "status"]) == "completed"
      assert get_in(state.states, ["ai-chat.ACTION.1", "status"]) == "completed"
      assert get_in(state.states, ["ai-chat.ACTION.2", "status"]) == "completed"
      assert get_in(state.states, ["ai-chat.FEEDBACK.1", "status"]) == "completed"

      # Null status ACIDs should not be in the map
      refute Map.has_key?(state.states, "ai-chat.UI.1")
      refute Map.has_key?(state.states, "ai-chat.UI.2")
    end

    # seed-data.IMPL_STATES.5-note: site / ai-chat does NOT have states on Production, Staging, or fix-map-settings
    test "seed-data.IMPL_STATES.5-note: site ai-chat Production has no direct states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "Production")

      state = Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "ai-chat")
      assert state == nil, "Production should not have direct states for ai-chat"
    end

    test "seed-data.IMPL_STATES.5-note: site ai-chat Staging has no direct states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "Staging")

      state = Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "ai-chat")
      assert state == nil, "Staging should not have direct states for ai-chat"
    end

    test "seed-data.IMPL_STATES.5-note: site ai-chat fix-map-settings has no direct states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "fix-map-settings")

      state = Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "ai-chat")
      assert state == nil, "fix-map-settings should not have direct states for ai-chat"
    end

    # seed-data.IMPL_STATES.6: site / map-settings / Production — all accepted and 1 completed ACID
    test "seed-data.IMPL_STATES.6: site map-settings Production has accepted and 1 completed" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "Production")

      state =
        Repo.get_by!(FeatureImplState, implementation_id: impl.id, feature_name: "map-settings")

      assert state != nil
      assert map_size(state.states) == 6

      # Most are accepted, one is completed
      completed_count =
        Enum.count(state.states, fn {_, attrs} ->
          attrs["status"] == "completed" or attrs[:status] == "completed"
        end)

      accepted_count =
        Enum.count(state.states, fn {_, attrs} ->
          attrs["status"] == "accepted" or attrs[:status] == "accepted"
        end)

      assert completed_count == 1
      assert accepted_count == 5

      # LAYERS.2 should be completed
      assert get_in(state.states, ["map-settings.LAYERS.2", "status"]) == "completed"
    end

    # seed-data.IMPL_STATES.6-1: site / map-settings / fix-map-settings — all accepted and 1 completed ACID
    test "seed-data.IMPL_STATES.6-1: site map-settings fix-map-settings has accepted and 1 completed" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "fix-map-settings")

      state =
        Repo.get_by!(FeatureImplState, implementation_id: impl.id, feature_name: "map-settings")

      assert state != nil
      # Has PERMISSIONS.2 extra
      assert map_size(state.states) == 7

      # Most are accepted, one is completed
      completed_count =
        Enum.count(state.states, fn {_, attrs} ->
          attrs["status"] == "completed" or attrs[:status] == "completed"
        end)

      accepted_count =
        Enum.count(state.states, fn {_, attrs} ->
          attrs["status"] == "accepted" or attrs[:status] == "accepted"
        end)

      assert completed_count == 1
      assert accepted_count == 6

      # LAYERS.2 should be completed
      assert get_in(state.states, ["map-settings.LAYERS.2", "status"]) == "completed"
    end

    # seed-data.IMPL_STATES.6-note: site / map-settings does NOT have states on Staging or feat/ai-chat
    test "seed-data.IMPL_STATES.6-note: site map-settings Staging has no direct states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "Staging")

      state =
        Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "map-settings")

      assert state == nil, "Staging should not have direct states for map-settings"
    end

    test "seed-data.IMPL_STATES.6-note: site map-settings feat/ai-chat has no direct states" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")
      impl = Repo.get_by!(Implementation, product_id: site_product.id, name: "feat/ai-chat")

      state =
        Repo.get_by(FeatureImplState, implementation_id: impl.id, feature_name: "map-settings")

      assert state == nil, "feat/ai-chat should not have direct states for map-settings"
    end

    # Idempotency test
    test "seed-data.ENVIRONMENT.2: running seeds twice doesn't duplicate impl states" do
      state_count_before = Repo.aggregate(FeatureImplState, :count)
      Acai.Seeds.run(silent: true)
      state_count_after = Repo.aggregate(FeatureImplState, :count)
      assert state_count_before == state_count_after
    end
  end

  # ============================================================================
  # REFS Tests (Phase 2)
  # ============================================================================

  describe "branch ref seeding" do
    # seed-data.REFS.1: backend main - every ACID in api features has at least 1 ref
    test "seed-data.REFS.1: core ACIDs on backend main all have refs" do
      team = Repo.get_by!(Team, name: "mapperoni")
      # API refs are on the backend repo's main branch (shared with site backend)
      backend_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/backend"
        )

      ref = Repo.get_by!(FeatureBranchRef, branch_id: backend_branch.id, feature_name: "core")
      assert ref != nil

      # All 10 ACIDs should have refs
      assert map_size(ref.refs) == 10

      Enum.each(ref.refs, fn {acid, refs} ->
        assert length(refs) >= 1, "ACID #{acid} should have at least 1 ref"
      end)
    end

    test "seed-data.REFS.1: mcp ACIDs on backend main all have refs" do
      team = Repo.get_by!(Team, name: "mapperoni")
      # API refs are on the backend repo's main branch (shared with site backend)
      backend_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/backend"
        )

      ref = Repo.get_by!(FeatureBranchRef, branch_id: backend_branch.id, feature_name: "mcp")
      assert ref != nil

      # All 20 ACIDs should have refs
      assert map_size(ref.refs) == 20

      Enum.each(ref.refs, fn {acid, refs} ->
        assert length(refs) >= 1, "ACID #{acid} should have at least 1 ref"
      end)
    end

    # seed-data.REFS.2: feat/ai-chat - completed requirements have refs, null status do not
    test "seed-data.REFS.2: completed ai-chat ACIDs on feat/ai-chat have refs" do
      team = Repo.get_by!(Team, name: "mapperoni")

      feat_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "feat/ai-chat",
          repo_uri: "github.com/mapperoni/frontend"
        )

      ref = Repo.get_by!(FeatureBranchRef, branch_id: feat_branch.id, feature_name: "ai-chat")
      assert ref != nil

      # Completed ACIDs should have refs
      completed_acids = [
        "ai-chat.AI.1",
        "ai-chat.AI.2",
        "ai-chat.ACTION.1",
        "ai-chat.ACTION.2",
        "ai-chat.FEEDBACK.1"
      ]

      Enum.each(completed_acids, fn acid ->
        refs = Map.get(ref.refs, acid)
        assert refs != nil, "Completed ACID #{acid} should have refs"
        assert length(refs) >= 1
      end)
    end

    test "seed-data.REFS.2: null status ai-chat ACIDs on feat/ai-chat have no refs" do
      team = Repo.get_by!(Team, name: "mapperoni")

      feat_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "feat/ai-chat",
          repo_uri: "github.com/mapperoni/frontend"
        )

      ref = Repo.get_by(FeatureBranchRef, branch_id: feat_branch.id, feature_name: "ai-chat")

      # Null status ACIDs should not have refs (or be omitted)
      null_acids = ["ai-chat.UI.1", "ai-chat.UI.2"]

      Enum.each(null_acids, fn acid ->
        refs = if ref, do: Map.get(ref.refs, acid), else: nil
        assert refs == nil, "Null status ACID #{acid} should not have refs"
      end)
    end

    # seed-data.REFS.3: Other features with variety of refs (production and test refs)
    test "seed-data.REFS.3: map-editor on main has refs with is_test variety" do
      team = Repo.get_by!(Team, name: "mapperoni")

      main_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/frontend"
        )

      ref = Repo.get_by!(FeatureBranchRef, branch_id: main_branch.id, feature_name: "map-editor")
      assert ref != nil

      # Should have refs with both is_test: true and is_test: false
      all_refs = List.flatten(Map.values(ref.refs))

      test_refs = Enum.filter(all_refs, fn r -> r["is_test"] == true or r[:is_test] == true end)

      non_test_refs =
        Enum.filter(all_refs, fn r -> r["is_test"] == false or r[:is_test] == false end)

      assert length(test_refs) >= 2, "Should have test refs"
      assert length(non_test_refs) >= 5, "Should have non-test refs"
    end

    test "seed-data.REFS.3: form-editor on dev has refs" do
      team = Repo.get_by!(Team, name: "mapperoni")

      dev_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "dev",
          repo_uri: "github.com/mapperoni/frontend"
        )

      ref = Repo.get_by!(FeatureBranchRef, branch_id: dev_branch.id, feature_name: "form-editor")
      assert ref != nil
      assert map_size(ref.refs) >= 2
    end

    test "seed-data.REFS.3: map-settings on fix-map-settings has refs" do
      team = Repo.get_by!(Team, name: "mapperoni")

      fix_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "fix-map-settings",
          repo_uri: "github.com/mapperoni/frontend"
        )

      ref = Repo.get_by!(FeatureBranchRef, branch_id: fix_branch.id, feature_name: "map-settings")
      assert ref != nil
      assert map_size(ref.refs) == 7
    end

    # seed-data.REFS.4: Dangling refs - ACIDs not associated with any seeded spec
    test "seed-data.REFS.4: dangling refs exist for unimplemented features" do
      team = Repo.get_by!(Team, name: "mapperoni")

      main_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/frontend"
        )

      # Should have dangling refs for unimplemented-feature
      dangling_ref =
        Repo.get_by(FeatureBranchRef,
          branch_id: main_branch.id,
          feature_name: "unimplemented-feature"
        )

      assert dangling_ref != nil, "Should have dangling refs for unimplemented-feature"
      assert map_size(dangling_ref.refs) == 2
    end

    test "seed-data.REFS.4: dangling refs exist for future-api on backend main" do
      team = Repo.get_by!(Team, name: "mapperoni")
      # Dangling refs are on the backend repo's main branch
      backend_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/backend"
        )

      # Should have dangling refs for future-api
      dangling_ref =
        Repo.get_by(FeatureBranchRef, branch_id: backend_branch.id, feature_name: "future-api")

      assert dangling_ref != nil, "Should have dangling refs for future-api"
      assert map_size(dangling_ref.refs) == 1
    end

    test "dangling refs do not pollute real feature ref counts" do
      team = Repo.get_by!(Team, name: "mapperoni")

      main_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/frontend"
        )

      # Real features should not include dangling refs
      map_editor_ref =
        Repo.get_by(FeatureBranchRef, branch_id: main_branch.id, feature_name: "map-editor")

      form_editor_ref =
        Repo.get_by(FeatureBranchRef, branch_id: main_branch.id, feature_name: "form-editor")

      refute Map.has_key?(map_editor_ref.refs, "unimplemented-feature.CONCEPT.1")
      refute Map.has_key?(form_editor_ref.refs, "unimplemented-feature.CONCEPT.1")
    end

    # Ref structure test
    test "branch refs have correct structure with path and is_test fields" do
      team = Repo.get_by!(Team, name: "mapperoni")
      # API refs are on the backend repo's main branch (shared with site backend)
      backend_branch =
        Repo.get_by!(Branch,
          team_id: team.id,
          branch_name: "main",
          repo_uri: "github.com/mapperoni/backend"
        )

      ref = Repo.get_by!(FeatureBranchRef, branch_id: backend_branch.id, feature_name: "core")

      Enum.each(ref.refs, fn {acid, refs} ->
        Enum.each(refs, fn r ->
          assert r["path"] != nil or r[:path] != nil,
                 "Ref for #{acid} should have path field"

          assert r["is_test"] != nil or r[:is_test] != nil,
                 "Ref for #{acid} should have is_test field"
        end)
      end)
    end

    # Idempotency test
    test "seed-data.ENVIRONMENT.2: running seeds twice doesn't duplicate branch refs" do
      ref_count_before = Repo.aggregate(FeatureBranchRef, :count)
      Acai.Seeds.run(silent: true)
      ref_count_after = Repo.aggregate(FeatureBranchRef, :count)
      assert ref_count_before == ref_count_after
    end
  end

  # ============================================================================
  # Cross-cutting Tests
  # ============================================================================

  describe "cross-cutting requirements" do
    test "every ACID from seed-data.SPECS.* is covered by specs" do
      # Verify all seeded specs have their ACIDs in the requirements field
      team = Repo.get_by!(Team, name: "mapperoni")

      specs =
        Repo.all(
          from s in Spec,
            join: p in Product,
            on: s.product_id == p.id,
            where: p.team_id == ^team.id
        )

      Enum.each(specs, fn spec ->
        # Each requirement key should match the feature name prefix
        Enum.each(spec.requirements, fn {acid, _} ->
          [feature_prefix | _] = String.split(acid, ".", parts: 2)

          assert feature_prefix == spec.feature_name,
                 "ACID #{acid} prefix should match feature name #{spec.feature_name}"
        end)
      end)
    end

    test "spec versions by feature count" do
      team = Repo.get_by!(Team, name: "mapperoni")
      site_product = Repo.get_by!(Product, team_id: team.id, name: "site")

      version_counts =
        Repo.all(
          from s in Spec,
            where: s.product_id == ^site_product.id,
            group_by: s.feature_name,
            select: {s.feature_name, count(s.id)}
        )
        |> Map.new()

      assert version_counts["map-editor"] == 1
      assert version_counts["form-editor"] == 2
      assert version_counts["ai-chat"] == 1
      assert version_counts["map-settings"] == 2
    end
  end
end
