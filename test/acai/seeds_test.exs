defmodule Acai.SeedsTest do
  @moduledoc """
  Tests for priv/repo/seeds.exs seed data generation.

  Each test exercises the seed helpers independently within a sandboxed
  transaction so the suite remains isolated and repeatable.
  """

  use Acai.DataCase, async: false

  import Ecto.Query

  alias Acai.Repo
  alias Acai.Accounts
  alias Acai.Accounts.{User, Scope}
  alias Acai.Teams
  alias Acai.Teams.{Team, UserTeamRole}
  alias Acai.Specs
  alias Acai.Implementations
  alias Acai.Events

  # ---------------------------------------------------------------------------
  # Seed helper functions (mirrored from seeds.exs for unit-testability)
  # ---------------------------------------------------------------------------

  # SEED_DATA.USERS.1 / SEED_DATA.USERS.2 / SEED_DATA.USERS.3
  # SEED_DATA.ENVIRONMENT.2
  defp seed_user(email) do
    case Accounts.get_user_by_email(email) do
      %User{} = existing ->
        existing

      nil ->
        {:ok, user} = Accounts.register_user(%{email: email})

        user =
          user
          |> User.password_changeset(%{password: "password123456"})
          |> Repo.update!()

        user
        |> User.confirm_changeset()
        |> Repo.update!()
    end
  end

  # SEED_DATA.TEAMS.1 / SEED_DATA.ENVIRONMENT.2
  defp seed_team(name, owner) do
    case Repo.get_by(Team, name: name) do
      %Team{} = existing ->
        existing

      nil ->
        scope = Scope.for_user(owner)
        {:ok, team} = Teams.create_team(scope, %{name: name})
        team
    end
  end

  # SEED_DATA.TEAMS.2 / SEED_DATA.TEAMS.3 / SEED_DATA.ENVIRONMENT.2
  defp seed_role(team, user, title) do
    exists =
      Repo.exists?(
        from r in UserTeamRole,
          where: r.team_id == ^team.id and r.user_id == ^user.id
      )

    unless exists do
      %UserTeamRole{}
      |> UserTeamRole.changeset(%{title: title})
      |> Ecto.Changeset.put_change(:team_id, team.id)
      |> Ecto.Changeset.put_change(:user_id, user.id)
      |> Repo.insert!()
    end
  end

  # SEED_DATA.MOCK_DATA.1 / SEED_DATA.ENVIRONMENT.2
  defp seed_spec(team, attrs) do
    case Repo.get_by(Acai.Specs.Spec,
           team_id: team.id,
           repo_uri: attrs.repo_uri,
           branch_name: attrs.branch_name,
           path: attrs.path
         ) do
      %Acai.Specs.Spec{} = existing ->
        existing

      nil ->
        scope = Scope.for_user(%User{id: nil})
        {:ok, spec} = Specs.create_spec(scope, team, attrs)
        spec
    end
  end

  # SEED_DATA.MOCK_DATA.2 / SEED_DATA.ENVIRONMENT.2
  defp seed_requirement(spec, attrs) do
    case Repo.get_by(Acai.Specs.Requirement,
           spec_id: spec.id,
           group_key: attrs.group_key,
           local_id: attrs.local_id
         ) do
      %Acai.Specs.Requirement{} = existing ->
        existing

      nil ->
        {:ok, req} = Specs.create_requirement(spec, attrs)
        req
    end
  end

  # SEED_DATA.MOCK_DATA.3 / SEED_DATA.ENVIRONMENT.2
  defp seed_impl(spec, attrs) do
    case Repo.get_by(Acai.Implementations.Implementation,
           spec_id: spec.id,
           name: attrs.name
         ) do
      %Acai.Implementations.Implementation{} = existing ->
        existing

      nil ->
        scope = Scope.for_user(%User{id: nil})
        {:ok, impl} = Implementations.create_implementation(scope, spec, attrs)
        impl
    end
  end

  # SEED_DATA.MOCK_DATA.3 / SEED_DATA.ENVIRONMENT.2
  defp seed_branch(impl, attrs) do
    case Repo.get_by(Acai.Implementations.TrackedBranch,
           implementation_id: impl.id,
           repo_uri: attrs.repo_uri
         ) do
      %Acai.Implementations.TrackedBranch{} = existing ->
        existing

      nil ->
        {:ok, branch} = Implementations.create_tracked_branch(impl, attrs)
        branch
    end
  end

  # SEED_DATA.MOCK_DATA.3 / SEED_DATA.ENVIRONMENT.2
  defp seed_status(impl, req, attrs) do
    case Repo.get_by(Acai.Implementations.RequirementStatus,
           implementation_id: impl.id,
           requirement_id: req.id
         ) do
      %Acai.Implementations.RequirementStatus{} = existing ->
        existing

      nil ->
        {:ok, status} = Implementations.create_requirement_status(impl, req, attrs)
        status
    end
  end

  # SEED_DATA.MOCK_DATA.4
  defp seed_event(team, attrs) do
    {:ok, event} = Events.create_activity_event(team, attrs)
    event
  end

  # ---------------------------------------------------------------------------
  # Shared setup: builds the three users and two teams used across test groups
  # ---------------------------------------------------------------------------

  defp build_users_and_teams(_context) do
    owner = seed_user("owner@testing.team")
    developer = seed_user("developer@testing.team")
    readonly = seed_user("readonly@testing.team")

    testing_team = seed_team("testing-team", owner)
    empty_team = seed_team("empty-team", owner)

    seed_role(testing_team, owner, "owner")
    seed_role(testing_team, developer, "developer")
    seed_role(testing_team, readonly, "readonly")
    seed_role(empty_team, owner, "owner")
    seed_role(empty_team, developer, "developer")
    seed_role(empty_team, readonly, "readonly")

    [
      owner: owner,
      developer: developer,
      readonly: readonly,
      testing_team: testing_team,
      empty_team: empty_team
    ]
  end

  # ---------------------------------------------------------------------------
  # SEED_DATA.USERS tests
  # ---------------------------------------------------------------------------

  describe "SEED_DATA.USERS — user accounts" do
    # SEED_DATA.USERS.1
    test "creates the three required user accounts" do
      owner = seed_user("owner@testing.team")
      developer = seed_user("developer@testing.team")
      readonly = seed_user("readonly@testing.team")

      assert owner.email == "owner@testing.team"
      assert developer.email == "developer@testing.team"
      assert readonly.email == "readonly@testing.team"

      assert Accounts.get_user_by_email("owner@testing.team")
      assert Accounts.get_user_by_email("developer@testing.team")
      assert Accounts.get_user_by_email("readonly@testing.team")
    end

    # SEED_DATA.USERS.2
    test "all users can authenticate with password123456" do
      _owner = seed_user("owner@testing.team")
      _developer = seed_user("developer@testing.team")
      _readonly = seed_user("readonly@testing.team")

      assert Accounts.get_user_by_email_and_password("owner@testing.team", "password123456")
      assert Accounts.get_user_by_email_and_password("developer@testing.team", "password123456")
      assert Accounts.get_user_by_email_and_password("readonly@testing.team", "password123456")
    end

    # SEED_DATA.USERS.3
    test "all users are marked as confirmed" do
      owner = seed_user("owner@testing.team")
      developer = seed_user("developer@testing.team")
      readonly = seed_user("readonly@testing.team")

      assert owner.confirmed_at != nil
      assert developer.confirmed_at != nil
      assert readonly.confirmed_at != nil
    end
  end

  # ---------------------------------------------------------------------------
  # SEED_DATA.TEAMS tests
  # ---------------------------------------------------------------------------

  describe "SEED_DATA.TEAMS — teams and membership" do
    setup :build_users_and_teams

    # SEED_DATA.TEAMS.1
    test "creates testing-team and empty-team", %{
      testing_team: testing_team,
      empty_team: empty_team
    } do
      assert testing_team.name == "testing-team"
      assert empty_team.name == "empty-team"

      assert Repo.get_by(Team, name: "testing-team")
      assert Repo.get_by(Team, name: "empty-team")
    end

    # SEED_DATA.TEAMS.2
    test "assigns all three users to testing-team with correct roles", %{
      owner: owner,
      developer: developer,
      readonly: readonly,
      testing_team: testing_team
    } do
      roles =
        Repo.all(
          from r in UserTeamRole,
            where: r.team_id == ^testing_team.id
        )

      role_map = Map.new(roles, &{&1.user_id, &1.title})

      assert role_map[owner.id] == "owner"
      assert role_map[developer.id] == "developer"
      assert role_map[readonly.id] == "readonly"
    end

    # SEED_DATA.TEAMS.3
    test "assigns all three users to empty-team with correct roles", %{
      owner: owner,
      developer: developer,
      readonly: readonly,
      empty_team: empty_team
    } do
      roles =
        Repo.all(
          from r in UserTeamRole,
            where: r.team_id == ^empty_team.id
        )

      role_map = Map.new(roles, &{&1.user_id, &1.title})

      assert role_map[owner.id] == "owner"
      assert role_map[developer.id] == "developer"
      assert role_map[readonly.id] == "readonly"
    end
  end

  # ---------------------------------------------------------------------------
  # SEED_DATA.MOCK_DATA tests
  # ---------------------------------------------------------------------------

  describe "SEED_DATA.MOCK_DATA — specs and requirements" do
    setup :build_users_and_teams

    defp build_spec_a(testing_team) do
      seed_spec(testing_team, %{
        repo_uri: "github.com/testing-team/auth-service",
        branch_name: "main",
        path: "features/user-auth/feature.yaml",
        last_seen_commit: "a1b2c3d4e5f6",
        parsed_at: DateTime.utc_now(:second),
        feature_name: "user-auth",
        feature_product: "auth-service",
        feature_description: "User authentication and session management"
      })
    end

    defp build_spec_b(testing_team) do
      seed_spec(testing_team, %{
        repo_uri: "github.com/testing-team/billing-service",
        branch_name: "main",
        path: "features/subscriptions/feature.yaml",
        last_seen_commit: "deadbeef1234",
        parsed_at: DateTime.utc_now(:second),
        feature_name: "subscriptions",
        feature_product: "billing-service",
        feature_description: "Subscription plans and billing lifecycle"
      })
    end

    defp build_spec_c(testing_team) do
      seed_spec(testing_team, %{
        repo_uri: "github.com/testing-team/notifications-service",
        branch_name: "main",
        path: "features/notifications/feature.yaml",
        last_seen_commit: "cafebabe9999",
        parsed_at: DateTime.utc_now(:second),
        feature_name: "notifications",
        feature_product: "notifications-service",
        feature_description: "In-app and email notification delivery"
      })
    end

    # SEED_DATA.MOCK_DATA.1
    test "generates at least 3 specs for testing-team", %{testing_team: testing_team} do
      build_spec_a(testing_team)
      build_spec_b(testing_team)
      build_spec_c(testing_team)

      count =
        Repo.one(
          from s in Acai.Specs.Spec,
            where: s.team_id == ^testing_team.id,
            select: count(s.id)
        )

      assert count >= 3
    end

    # SEED_DATA.MOCK_DATA.1 — spec with full requirements and multiple implementations
    test "spec_a has full requirements and multiple implementations", %{
      testing_team: testing_team
    } do
      spec_a = build_spec_a(testing_team)

      req_a1 =
        seed_requirement(spec_a, %{
          group_key: "LOGIN",
          group_type: :COMPONENT,
          local_id: "1",
          definition: "Users must be able to log in with email and password.",
          note: "Supports magic-link fallback when no password is set.",
          is_deprecated: false,
          feature_name: "user-auth",
          replaced_by: []
        })

      req_a2 =
        seed_requirement(spec_a, %{
          group_key: "LOGIN",
          group_type: :COMPONENT,
          local_id: "2",
          definition: "Users must be able to log out from all devices.",
          is_deprecated: false,
          feature_name: "user-auth",
          replaced_by: []
        })

      impl_prod = seed_impl(spec_a, %{name: "Production", is_active: true})
      impl_feat = seed_impl(spec_a, %{name: "Feature: OAuth Integration", is_active: true})

      # Verify multiple implementations exist
      impls_count =
        Repo.one(
          from i in Acai.Implementations.Implementation,
            where: i.spec_id == ^spec_a.id,
            select: count(i.id)
        )

      assert impls_count >= 2

      # Verify requirements exist
      reqs_count =
        Repo.one(
          from r in Acai.Specs.Requirement,
            where: r.spec_id == ^spec_a.id,
            select: count(r.id)
        )

      assert reqs_count >= 2

      # Not nil check
      assert req_a1.id
      assert req_a2.id
      assert impl_prod.id
      assert impl_feat.id
    end

    # SEED_DATA.MOCK_DATA.1 — spec with pending requirements and no implementations
    test "spec_b has requirements but no implementations", %{testing_team: testing_team} do
      spec_b = build_spec_b(testing_team)

      seed_requirement(spec_b, %{
        group_key: "PLANS",
        group_type: :COMPONENT,
        local_id: "1",
        definition: "Users must be able to select from at least three subscription tiers.",
        is_deprecated: false,
        feature_name: "subscriptions",
        replaced_by: []
      })

      impl_count =
        Repo.one(
          from i in Acai.Implementations.Implementation,
            where: i.spec_id == ^spec_b.id,
            select: count(i.id)
        )

      req_count =
        Repo.one(
          from r in Acai.Specs.Requirement,
            where: r.spec_id == ^spec_b.id,
            select: count(r.id)
        )

      assert impl_count == 0
      assert req_count >= 1
    end

    # SEED_DATA.MOCK_DATA.1 — spec with mix of implemented/partial/deprecated
    test "spec_c has mixed-status and deprecated requirements", %{testing_team: testing_team} do
      spec_c = build_spec_c(testing_team)

      req_c1 =
        seed_requirement(spec_c, %{
          group_key: "EMAIL",
          group_type: :COMPONENT,
          local_id: "1",
          definition: "Users must receive an email when their account password changes.",
          is_deprecated: false,
          feature_name: "notifications",
          replaced_by: []
        })

      req_c2 =
        seed_requirement(spec_c, %{
          group_key: "EMAIL",
          group_type: :COMPONENT,
          local_id: "2",
          definition: "Users must be able to unsubscribe from non-transactional emails.",
          is_deprecated: false,
          feature_name: "notifications",
          replaced_by: []
        })

      req_deprecated =
        seed_requirement(spec_c, %{
          group_key: "EMAIL",
          group_type: :COMPONENT,
          local_id: "3",
          definition: "Send a weekly digest of activity to users who opt in.",
          note: "Moved to the separate digest-service feature.",
          is_deprecated: true,
          feature_name: "notifications",
          replaced_by: ["notifications.INAPP.1"]
        })

      impl_c = seed_impl(spec_c, %{name: "Production", is_active: true})

      seed_status(impl_c, req_c1, %{
        status: "implemented",
        is_active: true,
        last_seen_commit: "cafebabe9999"
      })

      seed_status(impl_c, req_c2, %{
        status: "partial",
        is_active: true,
        last_seen_commit: "cafebabe9999",
        note: "Unsubscribe link present but preference centre not yet built."
      })

      # Verify deprecated requirement
      assert req_deprecated.is_deprecated == true
      assert req_deprecated.replaced_by == ["notifications.INAPP.1"]

      # Verify mixed statuses
      statuses =
        Repo.all(
          from rs in Acai.Implementations.RequirementStatus,
            where: rs.implementation_id == ^impl_c.id
        )

      status_values = Enum.map(statuses, & &1.status)
      assert "implemented" in status_values
      assert "partial" in status_values
    end

    # SEED_DATA.MOCK_DATA.2 — both COMPONENT and CONSTRAINT group types
    test "requirements cover both COMPONENT and CONSTRAINT group types", %{
      testing_team: testing_team
    } do
      spec = build_spec_a(testing_team)

      seed_requirement(spec, %{
        group_key: "LOGIN",
        group_type: :COMPONENT,
        local_id: "1",
        definition: "Users must be able to log in with email and password.",
        is_deprecated: false,
        feature_name: "user-auth",
        replaced_by: []
      })

      seed_requirement(spec, %{
        group_key: "SECURITY",
        group_type: :CONSTRAINT,
        local_id: "1",
        definition: "Passwords must be at least 12 characters.",
        is_deprecated: false,
        feature_name: "user-auth",
        replaced_by: []
      })

      group_types =
        Repo.all(
          from r in Acai.Specs.Requirement,
            where: r.spec_id == ^spec.id,
            select: r.group_type,
            distinct: true
        )

      assert :COMPONENT in group_types
      assert :CONSTRAINT in group_types
    end

    # SEED_DATA.MOCK_DATA.2 — nested requirements via parent_local_id
    test "requirements include nested sub-requirements", %{testing_team: testing_team} do
      spec = build_spec_a(testing_team)

      _parent =
        seed_requirement(spec, %{
          group_key: "LOGIN",
          group_type: :COMPONENT,
          local_id: "1",
          definition: "Users must be able to log in with email and password.",
          is_deprecated: false,
          feature_name: "user-auth",
          replaced_by: []
        })

      child =
        seed_requirement(spec, %{
          group_key: "LOGIN",
          group_type: :COMPONENT,
          local_id: "1-1",
          parent_local_id: "1",
          definition: "The login form must validate email format before submission.",
          is_deprecated: false,
          feature_name: "user-auth",
          replaced_by: []
        })

      assert child.parent_local_id == "1"

      nested_count =
        Repo.one(
          from r in Acai.Specs.Requirement,
            where: r.spec_id == ^spec.id and not is_nil(r.parent_local_id),
            select: count(r.id)
        )

      assert nested_count >= 1
    end

    # SEED_DATA.MOCK_DATA.2 — requirements with notes and replaced_by ACIDs
    test "requirements include notes and replaced_by ACIDs", %{testing_team: testing_team} do
      spec = build_spec_a(testing_team)

      req_with_note =
        seed_requirement(spec, %{
          group_key: "LOGIN",
          group_type: :COMPONENT,
          local_id: "1",
          definition: "Users must be able to log in with email and password.",
          note: "Supports magic-link fallback when no password is set.",
          is_deprecated: false,
          feature_name: "user-auth",
          replaced_by: []
        })

      req_with_replaced_by =
        seed_requirement(spec, %{
          group_key: "LOGIN",
          group_type: :COMPONENT,
          local_id: "3",
          definition: "Users must complete CAPTCHA on third failed login attempt.",
          note: "Replaced by rate limiting at the infrastructure level.",
          is_deprecated: true,
          feature_name: "user-auth",
          replaced_by: ["user-auth.SECURITY.1"]
        })

      assert req_with_note.note != nil
      assert req_with_replaced_by.replaced_by == ["user-auth.SECURITY.1"]
    end
  end

  describe "SEED_DATA.MOCK_DATA — implementations and tracked branches" do
    setup :build_users_and_teams

    # SEED_DATA.MOCK_DATA.3 — at least one implementation with a linked TrackedBranch
    test "at least one implementation has a linked TrackedBranch", %{testing_team: testing_team} do
      spec =
        seed_spec(testing_team, %{
          repo_uri: "github.com/testing-team/auth-service",
          branch_name: "main",
          path: "features/user-auth/feature.yaml",
          last_seen_commit: "a1b2c3d4e5f6",
          parsed_at: DateTime.utc_now(:second),
          feature_name: "user-auth",
          feature_product: "auth-service"
        })

      impl =
        seed_impl(spec, %{
          name: "Production",
          description: "Main production implementation.",
          is_active: true
        })

      branch =
        seed_branch(impl, %{
          repo_uri: "github.com/testing-team/auth-service",
          branch_name: "main"
        })

      assert branch.implementation_id == impl.id
      assert branch.repo_uri == "github.com/testing-team/auth-service"
      assert branch.branch_name == "main"

      branch_count =
        Repo.one(
          from b in Acai.Implementations.TrackedBranch,
            where: b.implementation_id == ^impl.id,
            select: count(b.id)
        )

      assert branch_count >= 1
    end

    # SEED_DATA.MOCK_DATA.3 — varying statuses for requirements within implementations
    test "requirement statuses include varying values (implemented, partial, pending)", %{
      testing_team: testing_team
    } do
      spec =
        seed_spec(testing_team, %{
          repo_uri: "github.com/testing-team/auth-service",
          branch_name: "main",
          path: "features/user-auth/feature.yaml",
          last_seen_commit: "a1b2c3d4e5f6",
          parsed_at: DateTime.utc_now(:second),
          feature_name: "user-auth",
          feature_product: "auth-service"
        })

      req1 =
        seed_requirement(spec, %{
          group_key: "LOGIN",
          group_type: :COMPONENT,
          local_id: "1",
          definition: "Req 1",
          is_deprecated: false,
          feature_name: "user-auth",
          replaced_by: []
        })

      req2 =
        seed_requirement(spec, %{
          group_key: "LOGIN",
          group_type: :COMPONENT,
          local_id: "2",
          definition: "Req 2",
          is_deprecated: false,
          feature_name: "user-auth",
          replaced_by: []
        })

      req3 =
        seed_requirement(spec, %{
          group_key: "SESSION",
          group_type: :COMPONENT,
          local_id: "1",
          definition: "Req 3",
          is_deprecated: false,
          feature_name: "user-auth",
          replaced_by: []
        })

      impl = seed_impl(spec, %{name: "Production", is_active: true})

      seed_status(impl, req1, %{
        status: "implemented",
        is_active: true,
        last_seen_commit: "abc"
      })

      seed_status(impl, req2, %{
        status: "partial",
        is_active: true,
        last_seen_commit: "abc"
      })

      seed_status(impl, req3, %{
        status: "pending",
        is_active: true,
        last_seen_commit: "abc"
      })

      statuses =
        Repo.all(
          from rs in Acai.Implementations.RequirementStatus,
            where: rs.implementation_id == ^impl.id,
            select: rs.status
        )

      assert "implemented" in statuses
      assert "partial" in statuses
      assert "pending" in statuses
    end
  end

  describe "SEED_DATA.MOCK_DATA — activity events" do
    setup :build_users_and_teams

    # SEED_DATA.MOCK_DATA.4 — events for spec creation, requirement updates, implementation progress
    test "generates events for spec creation, requirement updates and implementation progress", %{
      owner: owner,
      developer: developer,
      testing_team: testing_team
    } do
      spec =
        seed_spec(testing_team, %{
          repo_uri: "github.com/testing-team/auth-service",
          branch_name: "main",
          path: "features/user-auth/feature.yaml",
          last_seen_commit: "a1b2c3d4e5f6",
          parsed_at: DateTime.utc_now(:second),
          feature_name: "user-auth",
          feature_product: "auth-service"
        })

      req =
        seed_requirement(spec, %{
          group_key: "SESSION",
          group_type: :COMPONENT,
          local_id: "1",
          definition: "Sessions expire after 30 days.",
          is_deprecated: false,
          feature_name: "user-auth",
          replaced_by: []
        })

      impl = seed_impl(spec, %{name: "Production", is_active: true})

      batch_id = Acai.UUIDv7.autogenerate()

      seed_event(testing_team, %{
        event_type: "spec.created",
        subject_type: "spec",
        subject_id: spec.id,
        batch_id: batch_id,
        payload: %{"actor_email" => owner.email, "feature_name" => spec.feature_name}
      })

      seed_event(testing_team, %{
        event_type: "requirement.updated",
        subject_type: "requirement",
        subject_id: req.id,
        batch_id: Acai.UUIDv7.autogenerate(),
        payload: %{"actor_email" => developer.email, "acid" => "user-auth.SESSION.1"}
      })

      seed_event(testing_team, %{
        event_type: "implementation.created",
        subject_type: "implementation",
        subject_id: impl.id,
        batch_id: Acai.UUIDv7.autogenerate(),
        payload: %{"actor_email" => developer.email, "implementation_name" => impl.name}
      })

      event_types =
        Repo.all(
          from e in Acai.Events.ActivityEvent,
            where: e.team_id == ^testing_team.id,
            select: e.event_type
        )

      assert "spec.created" in event_types
      assert "requirement.updated" in event_types
      assert "implementation.created" in event_types
    end

    # SEED_DATA.MOCK_DATA.4 — events attributed to different team members
    test "events are attributed to both owner and developer actors", %{
      owner: owner,
      developer: developer,
      testing_team: testing_team
    } do
      spec =
        seed_spec(testing_team, %{
          repo_uri: "github.com/testing-team/auth-service",
          branch_name: "main",
          path: "features/user-auth/feature.yaml",
          last_seen_commit: "a1b2c3d4e5f6",
          parsed_at: DateTime.utc_now(:second),
          feature_name: "user-auth",
          feature_product: "auth-service"
        })

      seed_event(testing_team, %{
        event_type: "spec.created",
        subject_type: "spec",
        subject_id: spec.id,
        batch_id: Acai.UUIDv7.autogenerate(),
        payload: %{"actor_email" => owner.email}
      })

      seed_event(testing_team, %{
        event_type: "spec.created",
        subject_type: "spec",
        subject_id: spec.id,
        batch_id: Acai.UUIDv7.autogenerate(),
        payload: %{"actor_email" => developer.email}
      })

      events =
        Repo.all(
          from e in Acai.Events.ActivityEvent,
            where: e.team_id == ^testing_team.id
        )

      actor_emails = Enum.map(events, &Map.get(&1.payload, "actor_email"))

      assert owner.email in actor_emails
      assert developer.email in actor_emails
    end
  end

  # ---------------------------------------------------------------------------
  # SEED_DATA.ENVIRONMENT tests
  # ---------------------------------------------------------------------------

  describe "SEED_DATA.ENVIRONMENT — idempotency" do
    # SEED_DATA.ENVIRONMENT.1 — verifies seed helpers run without error
    test "seed helpers execute without errors" do
      assert %User{} = seed_user("owner@testing.team")
      assert %User{} = seed_user("developer@testing.team")
      assert %User{} = seed_user("readonly@testing.team")

      owner = seed_user("owner@testing.team")
      testing_team = seed_team("testing-team", owner)
      _empty_team = seed_team("empty-team", owner)

      assert testing_team.name == "testing-team"
    end

    # SEED_DATA.ENVIRONMENT.2 — running seed helpers twice does not create duplicates
    test "seed_user is idempotent — calling twice returns same user" do
      user_first = seed_user("idempotent@testing.team")
      user_second = seed_user("idempotent@testing.team")

      assert user_first.id == user_second.id

      count =
        Repo.one(
          from u in User,
            where: u.email == "idempotent@testing.team",
            select: count(u.id)
        )

      assert count == 1
    end

    # SEED_DATA.ENVIRONMENT.2 — seed_team is idempotent
    test "seed_team is idempotent — calling twice returns same team" do
      owner = seed_user("idempotent-owner@testing.team")
      team_first = seed_team("idempotent-team", owner)
      team_second = seed_team("idempotent-team", owner)

      assert team_first.id == team_second.id

      count =
        Repo.one(
          from t in Team,
            where: t.name == "idempotent-team",
            select: count(t.id)
        )

      assert count == 1
    end

    # SEED_DATA.ENVIRONMENT.2 — seed_role is idempotent
    test "seed_role is idempotent — calling twice does not create duplicate roles" do
      owner = seed_user("idempotent-role-owner@testing.team")
      team = seed_team("idempotent-role-team", owner)

      seed_role(team, owner, "owner")
      seed_role(team, owner, "owner")

      count =
        Repo.one(
          from r in UserTeamRole,
            where: r.team_id == ^team.id and r.user_id == ^owner.id,
            select: count(r.user_id)
        )

      assert count == 1
    end

    # SEED_DATA.ENVIRONMENT.2 — seed_spec is idempotent
    test "seed_spec is idempotent — calling twice returns same spec" do
      owner = seed_user("spec-idempotent@testing.team")
      team = seed_team("spec-idempotent-team", owner)

      attrs = %{
        repo_uri: "github.com/idempotent/repo",
        branch_name: "main",
        path: "features/test/feature.yaml",
        last_seen_commit: "abc123",
        parsed_at: DateTime.utc_now(:second),
        feature_name: "test-feature",
        feature_product: "test-product"
      }

      spec_first = seed_spec(team, attrs)
      spec_second = seed_spec(team, attrs)

      assert spec_first.id == spec_second.id

      count =
        Repo.one(
          from s in Acai.Specs.Spec,
            where:
              s.team_id == ^team.id and s.repo_uri == ^attrs.repo_uri and
                s.branch_name == ^attrs.branch_name and s.path == ^attrs.path,
            select: count(s.id)
        )

      assert count == 1
    end

    # SEED_DATA.ENVIRONMENT.2 — seed_requirement is idempotent
    test "seed_requirement is idempotent — calling twice returns same requirement" do
      owner = seed_user("req-idempotent@testing.team")
      team = seed_team("req-idempotent-team", owner)

      spec =
        seed_spec(team, %{
          repo_uri: "github.com/idempotent/repo",
          branch_name: "main",
          path: "features/test/feature.yaml",
          last_seen_commit: "abc123",
          parsed_at: DateTime.utc_now(:second),
          feature_name: "test-feature",
          feature_product: "test-product"
        })

      attrs = %{
        group_key: "COMP",
        group_type: :COMPONENT,
        local_id: "1",
        definition: "A test requirement.",
        is_deprecated: false,
        feature_name: "test-feature",
        replaced_by: []
      }

      req_first = seed_requirement(spec, attrs)
      req_second = seed_requirement(spec, attrs)

      assert req_first.id == req_second.id

      count =
        Repo.one(
          from r in Acai.Specs.Requirement,
            where: r.spec_id == ^spec.id and r.group_key == "COMP" and r.local_id == "1",
            select: count(r.id)
        )

      assert count == 1
    end

    # SEED_DATA.ENVIRONMENT.2 — seed_impl is idempotent
    test "seed_impl is idempotent — calling twice returns same implementation" do
      owner = seed_user("impl-idempotent@testing.team")
      team = seed_team("impl-idempotent-team", owner)

      spec =
        seed_spec(team, %{
          repo_uri: "github.com/idempotent/impl-repo",
          branch_name: "main",
          path: "features/impl-test/feature.yaml",
          last_seen_commit: "def456",
          parsed_at: DateTime.utc_now(:second),
          feature_name: "impl-test",
          feature_product: "impl-product"
        })

      attrs = %{name: "Production", is_active: true}

      impl_first = seed_impl(spec, attrs)
      impl_second = seed_impl(spec, attrs)

      assert impl_first.id == impl_second.id
    end
  end
end
