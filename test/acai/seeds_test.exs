defmodule Acai.SeedsTest do
  @moduledoc """
  Tests for priv/repo/seeds.exs seed data generation.
  Verifies the new data model with:
  - Products as first-class entities
  - Specs with JSONB requirements
  - SpecImplState and SpecImplRef tables
  - Implementations belonging to Products
  """

  use Acai.DataCase, async: false

  alias Acai.Repo
  alias Acai.Accounts
  alias Acai.Teams
  alias Acai.Products.Product
  alias Acai.Specs.{Spec, SpecImplState, SpecImplRef}
  alias Acai.Implementations.{Implementation, TrackedBranch}

  setup do
    # Clean slate for each test
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Repo)

    # Run seeds using the module
    Acai.Seeds.run()

    :ok
  end

  describe "user seeding" do
    test "creates admin user" do
      user = Accounts.get_user_by_email("admin@example.com")
      assert user != nil
    end

    test "creates developer user" do
      user = Accounts.get_user_by_email("developer@example.com")
      assert user != nil
    end

    test "creates readonly user" do
      user = Accounts.get_user_by_email("readonly@example.com")
      assert user != nil
    end

    test "idempotent: running seeds twice doesn't duplicate users" do
      user_count_before = Repo.aggregate(Accounts.User, :count)
      Acai.Seeds.run()
      user_count_after = Repo.aggregate(Accounts.User, :count)
      assert user_count_before == user_count_after
    end
  end

  describe "team seeding" do
    test "creates testing team" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      assert team != nil
    end

    test "assigns owner role to admin user" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      admin = Accounts.get_user_by_email("admin@example.com")

      role = Repo.get_by(Teams.UserTeamRole, team_id: team.id, user_id: admin.id)
      assert role != nil
      assert role.title == "owner"
    end

    test "assigns developer role to developer user" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      dev = Accounts.get_user_by_email("developer@example.com")

      role = Repo.get_by(Teams.UserTeamRole, team_id: team.id, user_id: dev.id)
      assert role != nil
      assert role.title == "developer"
    end

    test "idempotent: running seeds twice doesn't duplicate teams" do
      team_count_before = Repo.aggregate(Teams.Team, :count)
      Acai.Seeds.run()
      team_count_after = Repo.aggregate(Teams.Team, :count)
      assert team_count_before == team_count_after
    end
  end

  # data-model.PRODUCTS
  describe "product seeding" do
    test "creates auth-service product" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      assert product != nil
      assert product.description == "Authentication and authorization service"
    end

    test "creates billing-service product" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      product = Repo.get_by(Product, team_id: team.id, name: "billing-service")
      assert product != nil
    end

    test "creates notifications-service product" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      product = Repo.get_by(Product, team_id: team.id, name: "notifications-service")
      assert product != nil
    end

    test "idempotent: running seeds twice doesn't duplicate products" do
      product_count_before = Repo.aggregate(Product, :count)
      Acai.Seeds.run()
      product_count_after = Repo.aggregate(Product, :count)
      assert product_count_before == product_count_after
    end
  end

  # data-model.SPECS
  # data-model.SPECS.13: Requirements stored as JSONB
  describe "spec seeding" do
    test "creates user-auth spec" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")
      assert spec != nil
      assert spec.feature_description == "User authentication and session management"
    end

    test "user-auth spec has JSONB requirements" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")

      # data-model.SPECS.13-1: Requirements keyed by ACID
      assert is_map(spec.requirements)
      assert Map.has_key?(spec.requirements, "user-auth.LOGIN.1")
      assert Map.has_key?(spec.requirements, "user-auth.LOGIN.2")
      assert Map.has_key?(spec.requirements, "user-auth.SESSION.1")
    end

    test "requirement JSONB has correct structure" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")

      req = spec.requirements["user-auth.LOGIN.1"]
      assert req["definition"] == "Users must be able to log in with email and password."
      assert req["note"] == "Supports magic-link fallback when no password is set."
      assert req["is_deprecated"] == false
      assert req["replaced_by"] == []
    end

    test "spec belongs to a product" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")

      # data-model.SPECS.14: spec belongs to product
      product = Repo.get(Product, spec.product_id)
      assert product != nil
      assert product.name == "auth-service"
    end

    test "idempotent: running seeds twice doesn't duplicate specs" do
      spec_count_before = Repo.aggregate(Spec, :count)
      Acai.Seeds.run()
      spec_count_after = Repo.aggregate(Spec, :count)
      assert spec_count_before == spec_count_after
    end
  end

  # data-model.IMPLS
  describe "implementation seeding" do
    test "creates production implementation for auth-service" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      assert impl != nil
      assert impl.is_active == true
    end

    test "creates staging implementation for auth-service" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Staging")

      assert impl != nil
    end

    test "implementation belongs to correct team" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      assert impl.team_id == team.id
    end

    test "idempotent: running seeds twice doesn't duplicate implementations" do
      impl_count_before = Repo.aggregate(Implementation, :count)
      Acai.Seeds.run()
      impl_count_after = Repo.aggregate(Implementation, :count)
      assert impl_count_before == impl_count_after
    end
  end

  # data-model.BRANCHES
  describe "tracked branch seeding" do
    test "creates tracked branches for implementations" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      branches = Repo.all(from b in TrackedBranch, where: b.implementation_id == ^impl.id)
      assert length(branches) > 0
    end

    test "tracked branch has last_seen_commit" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      branch =
        Repo.get_by(TrackedBranch,
          implementation_id: impl.id,
          repo_uri: "github.com/acai-sh/auth-service"
        )

      assert branch != nil
      assert branch.last_seen_commit != nil
    end

    test "idempotent: running seeds twice doesn't duplicate tracked branches" do
      branch_count_before = Repo.aggregate(TrackedBranch, :count)
      Acai.Seeds.run()
      branch_count_after = Repo.aggregate(TrackedBranch, :count)
      assert branch_count_before == branch_count_after
    end
  end

  # data-model.SPEC_IMPL_STATES
  describe "spec_impl_state seeding" do
    test "creates spec_impl_state for auth spec and production impl" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      state = Repo.get_by(SpecImplState, spec_id: spec.id, implementation_id: impl.id)
      assert state != nil
    end

    test "spec_impl_state has JSONB states keyed by ACID" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      state = Repo.get_by(SpecImplState, spec_id: spec.id, implementation_id: impl.id)

      # data-model.SPEC_IMPL_STATES.4: States keyed by ACID
      assert is_map(state.states)
      assert Map.has_key?(state.states, "user-auth.LOGIN.1")
      assert Map.has_key?(state.states, "user-auth.SESSION.1")
    end

    test "spec_impl_state entry has correct status values" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      state = Repo.get_by(SpecImplState, spec_id: spec.id, implementation_id: impl.id)
      login_state = state.states["user-auth.LOGIN.1"]

      # data-model.SPEC_IMPL_STATES.4-3: Valid status values
      assert login_state["status"] in [
               "pending",
               "in_progress",
               "blocked",
               "completed",
               "rejected"
             ]

      assert login_state["updated_at"] != nil
    end

    test "idempotent: running seeds twice doesn't duplicate spec_impl_states" do
      state_count_before = Repo.aggregate(SpecImplState, :count)
      Acai.Seeds.run()
      state_count_after = Repo.aggregate(SpecImplState, :count)
      assert state_count_before == state_count_after
    end
  end

  # data-model.SPEC_IMPL_REFS
  describe "spec_impl_ref seeding" do
    test "creates spec_impl_ref for auth spec and production impl" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      ref = Repo.get_by(SpecImplRef, spec_id: spec.id, implementation_id: impl.id)
      assert ref != nil
    end

    test "spec_impl_ref has JSONB refs keyed by ACID" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      ref = Repo.get_by(SpecImplRef, spec_id: spec.id, implementation_id: impl.id)

      # data-model.SPEC_IMPL_REFS.4: Refs keyed by ACID
      assert is_map(ref.refs)
      assert Map.has_key?(ref.refs, "user-auth.LOGIN.1")
    end

    test "spec_impl_ref entry has correct reference structure" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      ref = Repo.get_by(SpecImplRef, spec_id: spec.id, implementation_id: impl.id)
      login_refs = ref.refs["user-auth.LOGIN.1"]

      # data-model.SPEC_IMPL_REFS.4-3: Each reference has repo, path, loc, is_test
      assert is_list(login_refs)
      first_ref = List.first(login_refs)
      assert first_ref["repo"] != nil
      assert first_ref["path"] != nil
      assert first_ref["loc"] != nil
      assert is_boolean(first_ref["is_test"])
    end

    test "spec_impl_ref has agent, commit, and pushed_at" do
      team = Repo.get_by(Teams.Team, name: "testing-team")
      spec = Repo.get_by(Spec, team_id: team.id, feature_name: "user-auth")
      product = Repo.get_by(Product, team_id: team.id, name: "auth-service")
      impl = Repo.get_by(Implementation, product_id: product.id, name: "Production")

      ref = Repo.get_by(SpecImplRef, spec_id: spec.id, implementation_id: impl.id)

      # data-model.SPEC_IMPL_REFS.5,6,7
      assert ref.agent != nil
      assert ref.commit != nil
      assert ref.pushed_at != nil
    end

    test "idempotent: running seeds twice doesn't duplicate spec_impl_refs" do
      ref_count_before = Repo.aggregate(SpecImplRef, :count)
      Acai.Seeds.run()
      ref_count_after = Repo.aggregate(SpecImplRef, :count)
      assert ref_count_before == ref_count_after
    end
  end
end
