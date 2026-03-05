# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# SEED_DATA.ENVIRONMENT.1
# SEED_DATA.ENVIRONMENT.2

import Ecto.Query

alias Acai.Repo
alias Acai.Accounts
alias Acai.Accounts.{User, Scope}
alias Acai.Teams
alias Acai.Teams.UserTeamRole
alias Acai.Specs
alias Acai.Implementations
alias Acai.Events

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

# SEED_DATA.USERS.1
# SEED_DATA.USERS.2
# SEED_DATA.USERS.3
# SEED_DATA.ENVIRONMENT.2
seed_user = fn email ->
  case Accounts.get_user_by_email(email) do
    %User{} = existing ->
      existing

    nil ->
      {:ok, user} = Accounts.register_user(%{email: email})

      # SEED_DATA.USERS.2
      user =
        user
        |> User.password_changeset(%{password: "password123456"})
        |> Repo.update!()

      # SEED_DATA.USERS.3
      user
      |> User.confirm_changeset()
      |> Repo.update!()
  end
end

# SEED_DATA.TEAMS.1
# SEED_DATA.ENVIRONMENT.2
seed_team = fn name, owner ->
  case Repo.get_by(Acai.Teams.Team, name: name) do
    %Acai.Teams.Team{} = existing ->
      existing

    nil ->
      scope = Scope.for_user(owner)
      {:ok, team} = Teams.create_team(scope, %{name: name})
      team
  end
end

# SEED_DATA.TEAMS.2
# SEED_DATA.TEAMS.3
# SEED_DATA.ENVIRONMENT.2
seed_role = fn team, user, title ->
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

# SEED_DATA.MOCK_DATA.1
# SEED_DATA.ENVIRONMENT.2
seed_spec = fn team, attrs ->
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

# SEED_DATA.MOCK_DATA.2
# SEED_DATA.ENVIRONMENT.2
seed_requirement = fn spec, attrs ->
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

# SEED_DATA.MOCK_DATA.3
# SEED_DATA.ENVIRONMENT.2
seed_impl = fn spec, attrs ->
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

# SEED_DATA.MOCK_DATA.3
# SEED_DATA.ENVIRONMENT.2
seed_branch = fn impl, attrs ->
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

# SEED_DATA.MOCK_DATA.3
# SEED_DATA.ENVIRONMENT.2
seed_status = fn impl, req, attrs ->
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
seed_event = fn team, attrs ->
  {:ok, event} = Events.create_activity_event(team, attrs)
  event
end

# ---------------------------------------------------------------------------
# SEED_DATA.USERS.1
# ---------------------------------------------------------------------------

owner_user = seed_user.("owner@testing.team")
developer_user = seed_user.("developer@testing.team")
readonly_user = seed_user.("readonly@testing.team")

IO.puts("Users seeded: #{owner_user.email}, #{developer_user.email}, #{readonly_user.email}")

# ---------------------------------------------------------------------------
# SEED_DATA.TEAMS.1
# ---------------------------------------------------------------------------

testing_team = seed_team.("testing-team", owner_user)
empty_team = seed_team.("empty-team", owner_user)

IO.puts("Teams seeded: #{testing_team.name}, #{empty_team.name}")

# ---------------------------------------------------------------------------
# SEED_DATA.TEAMS.2
# ---------------------------------------------------------------------------

seed_role.(testing_team, owner_user, "owner")
seed_role.(testing_team, developer_user, "developer")
seed_role.(testing_team, readonly_user, "readonly")

# ---------------------------------------------------------------------------
# SEED_DATA.TEAMS.3
# ---------------------------------------------------------------------------

seed_role.(empty_team, owner_user, "owner")
seed_role.(empty_team, developer_user, "developer")
seed_role.(empty_team, readonly_user, "readonly")

IO.puts("Roles seeded for both teams.")

# ---------------------------------------------------------------------------
# SEED_DATA.MOCK_DATA.1
# SEED_DATA.MOCK_DATA.2
# ---------------------------------------------------------------------------

spec_a =
  seed_spec.(testing_team, %{
    repo_uri: "github.com/testing-team/auth-service",
    branch_name: "main",
    path: "features/user-auth/feature.yaml",
    last_seen_commit: "a1b2c3d4e5f6",
    parsed_at: DateTime.utc_now(:second),
    feature_name: "user-auth",
    feature_product: "auth-service",
    feature_description: "User authentication and session management"
  })

req_a1 =
  seed_requirement.(spec_a, %{
    group_key: "LOGIN",
    group_type: :COMPONENT,
    local_id: "1",
    definition: "Users must be able to log in with email and password.",
    note: "Supports magic-link fallback when no password is set.",
    is_deprecated: false,
    feature_name: "user-auth",
    replaced_by: []
  })

_req_a1_1 =
  seed_requirement.(spec_a, %{
    group_key: "LOGIN",
    group_type: :COMPONENT,
    local_id: "1-1",
    parent_local_id: "1",
    definition: "The login form must validate email format before submission.",
    is_deprecated: false,
    feature_name: "user-auth",
    replaced_by: []
  })

_req_a1_2 =
  seed_requirement.(spec_a, %{
    group_key: "LOGIN",
    group_type: :COMPONENT,
    local_id: "1-2",
    parent_local_id: "1",
    definition: "Failed login attempts must show a generic error message.",
    is_deprecated: false,
    feature_name: "user-auth",
    replaced_by: []
  })

req_a2 =
  seed_requirement.(spec_a, %{
    group_key: "LOGIN",
    group_type: :COMPONENT,
    local_id: "2",
    definition: "Users must be able to log out from all devices.",
    is_deprecated: false,
    feature_name: "user-auth",
    replaced_by: []
  })

req_a3 =
  seed_requirement.(spec_a, %{
    group_key: "SESSION",
    group_type: :COMPONENT,
    local_id: "1",
    definition: "Sessions must expire after 30 days of inactivity.",
    note: "Originally 14 days; extended per product decision.",
    is_deprecated: false,
    feature_name: "user-auth",
    replaced_by: []
  })

# SEED_DATA.MOCK_DATA.2
req_a_sec1 =
  seed_requirement.(spec_a, %{
    group_key: "SECURITY",
    group_type: :CONSTRAINT,
    local_id: "1",
    definition: "Passwords must be at least 12 characters.",
    is_deprecated: false,
    feature_name: "user-auth",
    replaced_by: []
  })

# SEED_DATA.MOCK_DATA.2
_req_a_sec2 =
  seed_requirement.(spec_a, %{
    group_key: "SECURITY",
    group_type: :CONSTRAINT,
    local_id: "2",
    definition: "All authentication tokens must be hashed using SHA-256 before storage.",
    is_deprecated: false,
    feature_name: "user-auth",
    replaced_by: []
  })

# SEED_DATA.MOCK_DATA.2
_req_a_old =
  seed_requirement.(spec_a, %{
    group_key: "LOGIN",
    group_type: :COMPONENT,
    local_id: "3",
    definition: "Users must complete CAPTCHA on third failed login attempt.",
    note: "Replaced by rate limiting at the infrastructure level.",
    is_deprecated: true,
    feature_name: "user-auth",
    replaced_by: ["user-auth.SECURITY.1"]
  })

# ---------------------------------------------------------------------------
# SEED_DATA.MOCK_DATA.3
# ---------------------------------------------------------------------------

impl_a_prod =
  seed_impl.(spec_a, %{
    name: "Production",
    description: "Main production implementation tracked against the main branch.",
    is_active: true
  })

# SEED_DATA.MOCK_DATA.3
_branch_a_prod =
  seed_branch.(impl_a_prod, %{
    repo_uri: "github.com/testing-team/auth-service",
    branch_name: "main"
  })

# SEED_DATA.MOCK_DATA.3
seed_status.(impl_a_prod, req_a1, %{
  status: "completed",
  is_active: true,
  last_seen_commit: "a1b2c3d4e5f6",
  note: "Fully completed and covered by tests."
})

seed_status.(impl_a_prod, req_a2, %{
  status: "completed",
  is_active: true,
  last_seen_commit: "a1b2c3d4e5f6"
})

seed_status.(impl_a_prod, req_a3, %{
  status: "completed",
  is_active: true,
  last_seen_commit: "a1b2c3d4e5f6"
})

seed_status.(impl_a_prod, req_a_sec1, %{
  status: "completed",
  is_active: true,
  last_seen_commit: "a1b2c3d4e5f6"
})

# SEED_DATA.MOCK_DATA.3
impl_a_feat =
  seed_impl.(spec_a, %{
    name: "Feature: OAuth Integration",
    description: "Adds OAuth2 provider support alongside password auth.",
    is_active: true
  })

_branch_a_feat =
  seed_branch.(impl_a_feat, %{
    repo_uri: "github.com/testing-team/auth-service",
    branch_name: "feat/oauth-integration"
  })

seed_status.(impl_a_feat, req_a1, %{
  status: "partial",
  is_active: true,
  last_seen_commit: "f6e5d4c3b2a1",
  note: "OAuth flow completed; password path not yet touched."
})

seed_status.(impl_a_feat, req_a2, %{
  status: "pending",
  is_active: true,
  last_seen_commit: "f6e5d4c3b2a1"
})

IO.puts("Spec A (user-auth) seeded with implementations.")

# ---------------------------------------------------------------------------
# SEED_DATA.MOCK_DATA.1
# SEED_DATA.MOCK_DATA.2
# ---------------------------------------------------------------------------

spec_b =
  seed_spec.(testing_team, %{
    repo_uri: "github.com/testing-team/billing-service",
    branch_name: "main",
    path: "features/subscriptions/feature.yaml",
    last_seen_commit: "deadbeef1234",
    parsed_at: DateTime.utc_now(:second),
    feature_name: "subscriptions",
    feature_product: "billing-service",
    feature_description: "Subscription plans and billing lifecycle"
  })

_req_b1 =
  seed_requirement.(spec_b, %{
    group_key: "PLANS",
    group_type: :COMPONENT,
    local_id: "1",
    definition: "Users must be able to select from at least three subscription tiers.",
    is_deprecated: false,
    feature_name: "subscriptions",
    replaced_by: []
  })

_req_b1_1 =
  seed_requirement.(spec_b, %{
    group_key: "PLANS",
    group_type: :COMPONENT,
    local_id: "1-1",
    parent_local_id: "1",
    definition: "Each tier must display its feature set and monthly/annual pricing.",
    note: "Design pending approval from product.",
    is_deprecated: false,
    feature_name: "subscriptions",
    replaced_by: []
  })

_req_b2 =
  seed_requirement.(spec_b, %{
    group_key: "PLANS",
    group_type: :COMPONENT,
    local_id: "2",
    definition: "Users must be able to upgrade or downgrade their plan at any time.",
    is_deprecated: false,
    feature_name: "subscriptions",
    replaced_by: []
  })

# SEED_DATA.MOCK_DATA.2
_req_b_pay1 =
  seed_requirement.(spec_b, %{
    group_key: "PAYMENTS",
    group_type: :CONSTRAINT,
    local_id: "1",
    definition: "All payment processing must comply with PCI-DSS Level 1.",
    note: "Delegate to Stripe; no raw card data stored in the application.",
    is_deprecated: false,
    feature_name: "subscriptions",
    replaced_by: []
  })

# SEED_DATA.MOCK_DATA.2
_req_b_pay2 =
  seed_requirement.(spec_b, %{
    group_key: "PAYMENTS",
    group_type: :CONSTRAINT,
    local_id: "2",
    definition: "Webhook events from the payment provider must be idempotent.",
    is_deprecated: false,
    feature_name: "subscriptions",
    replaced_by: []
  })

# SEED_DATA.MOCK_DATA.1
IO.puts("Spec B (subscriptions) seeded with no implementations.")

# ---------------------------------------------------------------------------
# SEED_DATA.MOCK_DATA.1
# SEED_DATA.MOCK_DATA.2
# ---------------------------------------------------------------------------

spec_c =
  seed_spec.(testing_team, %{
    repo_uri: "github.com/testing-team/notifications-service",
    branch_name: "main",
    path: "features/notifications/feature.yaml",
    last_seen_commit: "cafebabe9999",
    parsed_at: DateTime.utc_now(:second),
    feature_name: "notifications",
    feature_product: "notifications-service",
    feature_description: "In-app and email notification delivery"
  })

req_c1 =
  seed_requirement.(spec_c, %{
    group_key: "EMAIL",
    group_type: :COMPONENT,
    local_id: "1",
    definition: "Users must receive an email when their account password changes.",
    is_deprecated: false,
    feature_name: "notifications",
    replaced_by: []
  })

req_c1_1 =
  seed_requirement.(spec_c, %{
    group_key: "EMAIL",
    group_type: :COMPONENT,
    local_id: "1-1",
    parent_local_id: "1",
    definition: "The password-change email must include a revocation link.",
    is_deprecated: false,
    feature_name: "notifications",
    replaced_by: []
  })

req_c2 =
  seed_requirement.(spec_c, %{
    group_key: "EMAIL",
    group_type: :COMPONENT,
    local_id: "2",
    definition: "Users must be able to unsubscribe from non-transactional emails.",
    is_deprecated: false,
    feature_name: "notifications",
    replaced_by: []
  })

# SEED_DATA.MOCK_DATA.2
req_c3 =
  seed_requirement.(spec_c, %{
    group_key: "EMAIL",
    group_type: :COMPONENT,
    local_id: "3",
    definition: "Send a weekly digest of activity to users who opt in.",
    note: "Moved to the separate digest-service feature.",
    is_deprecated: true,
    feature_name: "notifications",
    replaced_by: ["notifications.INAPP.1"]
  })

req_c_inapp1 =
  seed_requirement.(spec_c, %{
    group_key: "INAPP",
    group_type: :COMPONENT,
    local_id: "1",
    definition: "Users must see a notification badge with unread count.",
    is_deprecated: false,
    feature_name: "notifications",
    replaced_by: []
  })

_req_c_inapp1_1 =
  seed_requirement.(spec_c, %{
    group_key: "INAPP",
    group_type: :COMPONENT,
    local_id: "1-1",
    parent_local_id: "1",
    definition: "The badge must update in real-time via LiveView.",
    is_deprecated: false,
    feature_name: "notifications",
    replaced_by: []
  })

# SEED_DATA.MOCK_DATA.2
req_c_rel1 =
  seed_requirement.(spec_c, %{
    group_key: "RELIABILITY",
    group_type: :CONSTRAINT,
    local_id: "1",
    definition: "Email delivery must be attempted at least 3 times before marking as failed.",
    is_deprecated: false,
    feature_name: "notifications",
    replaced_by: []
  })

# SEED_DATA.MOCK_DATA.2
_req_c_rel2 =
  seed_requirement.(spec_c, %{
    group_key: "RELIABILITY",
    group_type: :CONSTRAINT,
    local_id: "2",
    definition: "Failed deliveries must be logged with reason and timestamp.",
    is_deprecated: false,
    feature_name: "notifications",
    replaced_by: []
  })

# SEED_DATA.MOCK_DATA.3
impl_c_prod =
  seed_impl.(spec_c, %{
    name: "Production",
    description: "Production notification pipeline.",
    is_active: true
  })

# SEED_DATA.MOCK_DATA.3
_branch_c_prod =
  seed_branch.(impl_c_prod, %{
    repo_uri: "github.com/testing-team/notifications-service",
    branch_name: "main"
  })

# SEED_DATA.MOCK_DATA.1
# SEED_DATA.MOCK_DATA.3
seed_status.(impl_c_prod, req_c1, %{
  status: "completed",
  is_active: true,
  last_seen_commit: "cafebabe9999"
})

seed_status.(impl_c_prod, req_c1_1, %{
  status: "completed",
  is_active: true,
  last_seen_commit: "cafebabe9999"
})

seed_status.(impl_c_prod, req_c2, %{
  status: "partial",
  is_active: true,
  last_seen_commit: "cafebabe9999",
  note: "Unsubscribe link present but preference centre not yet built."
})

seed_status.(impl_c_prod, req_c_inapp1, %{
  status: "pending",
  is_active: true,
  last_seen_commit: "cafebabe9999"
})

seed_status.(impl_c_prod, req_c_rel1, %{
  status: "completed",
  is_active: true,
  last_seen_commit: "cafebabe9999"
})

IO.puts("Spec C (notifications) seeded with mixed-status implementation.")

# ---------------------------------------------------------------------------
# SEED_DATA.MOCK_DATA.4
# ---------------------------------------------------------------------------

batch_id = Acai.UUIDv7.autogenerate()

seed_event.(testing_team, %{
  event_type: "spec.created",
  subject_type: "spec",
  subject_id: spec_a.id,
  batch_id: batch_id,
  payload: %{
    "actor_email" => owner_user.email,
    "feature_name" => spec_a.feature_name,
    "repo_uri" => spec_a.repo_uri
  }
})

seed_event.(testing_team, %{
  event_type: "spec.created",
  subject_type: "spec",
  subject_id: spec_b.id,
  batch_id: batch_id,
  payload: %{
    "actor_email" => developer_user.email,
    "feature_name" => spec_b.feature_name,
    "repo_uri" => spec_b.repo_uri
  }
})

seed_event.(testing_team, %{
  event_type: "spec.created",
  subject_type: "spec",
  subject_id: spec_c.id,
  batch_id: Acai.UUIDv7.autogenerate(),
  payload: %{
    "actor_email" => owner_user.email,
    "feature_name" => spec_c.feature_name,
    "repo_uri" => spec_c.repo_uri
  }
})

seed_event.(testing_team, %{
  event_type: "requirement.deprecated",
  subject_type: "requirement",
  subject_id: req_c3.id,
  batch_id: Acai.UUIDv7.autogenerate(),
  payload: %{
    "actor_email" => owner_user.email,
    "acid" => "notifications.EMAIL.3",
    "replaced_by" => ["notifications.INAPP.1"]
  }
})

seed_event.(testing_team, %{
  event_type: "requirement.updated",
  subject_type: "requirement",
  subject_id: req_a3.id,
  batch_id: Acai.UUIDv7.autogenerate(),
  payload: %{
    "actor_email" => developer_user.email,
    "acid" => "user-auth.SESSION.1",
    "change" => "Extended session timeout from 14 to 30 days."
  }
})

seed_event.(testing_team, %{
  event_type: "implementation.created",
  subject_type: "implementation",
  subject_id: impl_a_prod.id,
  batch_id: Acai.UUIDv7.autogenerate(),
  payload: %{
    "actor_email" => developer_user.email,
    "implementation_name" => impl_a_prod.name,
    "feature_name" => spec_a.feature_name
  }
})

seed_event.(testing_team, %{
  event_type: "requirement_status.updated",
  subject_type: "implementation",
  subject_id: impl_a_feat.id,
  batch_id: Acai.UUIDv7.autogenerate(),
  payload: %{
    "actor_email" => developer_user.email,
    "implementation_name" => impl_a_feat.name,
    "status" => "partial",
    "acid" => "user-auth.LOGIN.1"
  }
})

seed_event.(testing_team, %{
  event_type: "requirement_status.updated",
  subject_type: "implementation",
  subject_id: impl_c_prod.id,
  batch_id: Acai.UUIDv7.autogenerate(),
  payload: %{
    "actor_email" => owner_user.email,
    "implementation_name" => impl_c_prod.name,
    "status" => "partial",
    "acid" => "notifications.EMAIL.2"
  }
})

IO.puts("Activity events seeded for testing-team.")
IO.puts("Seed data complete.")
