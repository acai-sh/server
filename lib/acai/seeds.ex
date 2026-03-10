defmodule Acai.Seeds do
  @moduledoc """
  Database seeding functionality for the new data model.

  This module is used by priv/repo/seeds.exs to populate the database
  with sample data demonstrating the new data model:
  - Products as first-class entities
  - Specs with JSONB requirements
  - SpecImplState and SpecImplRef tables
  - Implementations belonging to Products
  """

  import Ecto.Query

  alias Acai.Repo
  alias Acai.Accounts
  alias Acai.Teams.{Team, UserTeamRole}
  alias Acai.Products.Product
  alias Acai.Specs.{Spec, SpecImplState, SpecImplRef}
  alias Acai.Implementations.{Implementation, TrackedBranch}

  @doc """
  Runs all seeds.
  """
  def run do
    users = seed_users()
    team = seed_team("testing-team")
    seed_roles(team, users)

    products = seed_products(team)
    specs = seed_specs(team, products)
    impls = seed_implementations(team, products)
    seed_tracked_branches(impls)
    seed_spec_impl_states(specs, impls)
    seed_spec_impl_refs(specs, impls)

    IO.puts("\n=== Seeding Complete ===")
    IO.puts("")
    IO.puts("Sample data created:")
    IO.puts("  - Users: #{Enum.map(users, & &1.email) |> Enum.join(", ")}")
    IO.puts("  - Team: #{team.name}")
    IO.puts("  - Products: #{Enum.map(products, & &1.name) |> Enum.join(", ")}")
    IO.puts("  - Specs: #{Enum.map(specs, & &1.feature_name) |> Enum.join(", ")}")
    IO.puts("  - Implementations: Production, Staging environments")
    IO.puts("")
    IO.puts("All passwords are: Password123!")

    :ok
  end

  # ---------------------------------------------------------------------------
  # User Seeding
  # ---------------------------------------------------------------------------

  defp seed_users do
    IO.puts("\n=== Seeding Users ===")

    [
      seed_user("admin@example.com"),
      seed_user("developer@example.com"),
      seed_user("readonly@example.com")
    ]
  end

  defp seed_user(email) do
    case Accounts.get_user_by_email(email) do
      nil ->
        {:ok, user} = Accounts.register_user(%{email: email, password: "Password123!"})
        IO.puts("Created user: #{email}")
        user

      user ->
        IO.puts("User already exists: #{email}")
        user
    end
  end

  # ---------------------------------------------------------------------------
  # Team Seeding
  # ---------------------------------------------------------------------------

  defp seed_team(name) do
    IO.puts("\n=== Seeding Teams ===")

    case Repo.get_by(Team, name: name) do
      nil ->
        {:ok, team} = Repo.insert(%Team{name: name})
        IO.puts("Created team: #{name}")
        team

      team ->
        IO.puts("Team already exists: #{name}")
        team
    end
  end

  # ---------------------------------------------------------------------------
  # Role Seeding
  # ---------------------------------------------------------------------------

  defp seed_roles(team, [admin, dev, readonly]) do
    IO.puts("\n=== Seeding Roles ===")

    seed_role(team, admin, "owner")
    seed_role(team, dev, "developer")
    seed_role(team, readonly, "readonly")
  end

  defp seed_role(team, user, title) do
    existing =
      Repo.one(from r in UserTeamRole, where: r.team_id == ^team.id and r.user_id == ^user.id)

    if existing do
      IO.puts("Role already exists for user #{user.email} in team #{team.name}")
      existing
    else
      {:ok, role} =
        Repo.insert(%UserTeamRole{team_id: team.id, user_id: user.id, title: title})

      IO.puts("Assigned role #{title} to #{user.email} in team #{team.name}")
      role
    end
  end

  # ---------------------------------------------------------------------------
  # Product Seeding
  # ---------------------------------------------------------------------------

  # data-model.PRODUCTS
  defp seed_products(team) do
    IO.puts("\n=== Seeding Products ===")

    auth_product =
      seed_product(team, "auth-service", %{
        description: "Authentication and authorization service"
      })

    billing_product =
      seed_product(team, "billing-service", %{
        description: "Billing and payment processing service"
      })

    notifications_product =
      seed_product(team, "notifications-service", %{
        description: "Email and push notification service"
      })

    [auth_product, billing_product, notifications_product]
  end

  # data-model.PRODUCTS.2: product belongs to team
  # data-model.PRODUCTS.6: (team_id, name) is unique
  defp seed_product(team, name, attrs) do
    existing = Repo.one(from p in Product, where: p.team_id == ^team.id and p.name == ^name)

    if existing do
      IO.puts("Product already exists: #{name} in team #{team.name}")
      existing
    else
      attrs =
        Map.merge(
          %{
            name: name,
            description: "Sample product for demonstration",
            is_active: true,
            team_id: team.id
          },
          attrs
        )

      {:ok, product} = Repo.insert(Product.changeset(%Product{}, attrs))
      IO.puts("Created product: #{name} in team #{team.name}")
      product
    end
  end

  # ---------------------------------------------------------------------------
  # Spec Seeding
  # ---------------------------------------------------------------------------

  # data-model.SPECS
  defp seed_specs(team, [auth_product, billing_product, notifications_product]) do
    IO.puts("\n=== Seeding Specs with JSONB Requirements ===")

    auth_spec = seed_auth_spec(team, auth_product)
    billing_spec = seed_billing_spec(team, billing_product)
    notifications_spec = seed_notifications_spec(team, notifications_product)

    [auth_spec, billing_spec, notifications_spec]
  end

  # data-model.SPECS.13: Requirements are stored as JSONB keyed by ACID
  defp seed_auth_spec(team, product) do
    seed_spec(team, product, %{
      feature_name: "user-auth",
      feature_description: "User authentication and session management",
      repo_uri: "github.com/acai-sh/auth-service",
      branch_name: "main",
      path: "features/auth/user-auth.yaml",
      requirements: %{
        "user-auth.LOGIN.1" => %{
          "definition" => "Users must be able to log in with email and password.",
          "note" => "Supports magic-link fallback when no password is set.",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "user-auth.LOGIN.1-1" => %{
          "definition" => "The login form must validate email format before submission.",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "user-auth.LOGIN.2" => %{
          "definition" =>
            "Failed login attempts must be rate-limited to prevent brute force attacks.",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "user-auth.SESSION.1" => %{
          "definition" => "Sessions must expire after 24 hours of inactivity.",
          "note" => "Configurable per-tenant",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "user-auth.SESSION.2" => %{
          "definition" => "Users must be able to view and revoke active sessions.",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }
    })
  end

  defp seed_billing_spec(team, product) do
    seed_spec(team, product, %{
      feature_name: "subscription-management",
      feature_description: "Subscription lifecycle management",
      repo_uri: "github.com/acai-sh/billing-service",
      branch_name: "main",
      path: "features/billing/subscription.yaml",
      requirements: %{
        "subscription-management.BILLING.1" => %{
          "definition" => "Users must be able to upgrade their subscription tier.",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "subscription-management.BILLING.2" => %{
          "definition" => "Prorated charges must be calculated on mid-cycle upgrades.",
          "note" => "Uses Stripe's proration logic",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "subscription-management.BILLING.3" => %{
          "definition" => "Failed payments must retry with exponential backoff.",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }
    })
  end

  defp seed_notifications_spec(team, product) do
    seed_spec(team, product, %{
      feature_name: "email-delivery",
      feature_description: "Reliable email delivery system",
      repo_uri: "github.com/acai-sh/notifications-service",
      branch_name: "main",
      path: "features/notifications/email.yaml",
      requirements: %{
        "email-delivery.NOTIFY.1" => %{
          "definition" => "Emails must be queued for delivery within 5 seconds.",
          "is_deprecated" => false,
          "replaced_by" => []
        },
        "email-delivery.NOTIFY.2" => %{
          "definition" => "Bounced emails must be tracked and retried with backoff.",
          "is_deprecated" => false,
          "replaced_by" => []
        }
      }
    })
  end

  # data-model.SPECS.14: spec belongs to product
  # data-model.SPECS.13: requirements stored as JSONB
  defp seed_spec(team, product, attrs) do
    unique_suffix = :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

    defaults = %{
      repo_uri: "github.com/example/repo",
      branch_name: "main",
      path: "features/sample-#{unique_suffix}.yaml",
      last_seen_commit: "abc#{unique_suffix}",
      parsed_at: DateTime.utc_now(:second),
      feature_name: "sample-feature-#{unique_suffix}",
      feature_description: "A sample feature for demonstration",
      feature_version: "1.0.0",
      raw_content: "feature:\n  name: sample",
      requirements: %{},
      team_id: team.id,
      product_id: product.id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from s in Spec,
          where: s.team_id == ^team.id,
          where: s.feature_name == ^attrs.feature_name
      )

    if existing do
      IO.puts("Spec already exists: #{attrs.feature_name} in team #{team.name}")
      existing
    else
      {:ok, spec} = Repo.insert(Spec.changeset(%Spec{}, attrs))
      IO.puts("Created spec: #{spec.feature_name} in product #{product.name}")
      spec
    end
  end

  # ---------------------------------------------------------------------------
  # Implementation Seeding
  # ---------------------------------------------------------------------------

  # data-model.IMPLS
  defp seed_implementations(team, [auth_product | _]) do
    IO.puts("\n=== Seeding Implementations ===")

    # data-model.IMPLS.2: Implementations belong to products, not specs
    auth_prod_impl =
      seed_implementation(team, auth_product, %{
        name: "Production",
        description: "Production environment for auth service"
      })

    auth_staging_impl =
      seed_implementation(team, auth_product, %{
        name: "Staging",
        description: "Staging environment for auth service"
      })

    # Get billing product for the third implementation
    billing_product = Repo.get_by(Product, team_id: team.id, name: "billing-service")

    billing_prod_impl =
      seed_implementation(team, billing_product, %{
        name: "Production",
        description: "Production environment for billing service"
      })

    [auth_prod_impl, auth_staging_impl, billing_prod_impl]
  end

  # data-model.IMPLS.2: implementation belongs to product
  defp seed_implementation(team, product, attrs) do
    defaults = %{
      name: "production",
      description: "Production environment",
      is_active: true,
      team_id: team.id,
      product_id: product.id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from i in Implementation,
          where: i.product_id == ^product.id and i.name == ^attrs.name
      )

    if existing do
      IO.puts("Implementation already exists: #{attrs.name} for product #{product.name}")
      existing
    else
      {:ok, impl} = Repo.insert(Implementation.changeset(%Implementation{}, attrs))
      IO.puts("Created implementation: #{impl.name} for product #{product.name}")
      impl
    end
  end

  # ---------------------------------------------------------------------------
  # Tracked Branch Seeding
  # ---------------------------------------------------------------------------

  # data-model.BRANCHES
  defp seed_tracked_branches([auth_prod_impl, auth_staging_impl | _]) do
    IO.puts("\n=== Seeding Tracked Branches ===")

    seed_tracked_branch(auth_prod_impl, %{
      repo_uri: "github.com/acai-sh/auth-service",
      branch_name: "main",
      last_seen_commit: "a1b2c3d4e5f6"
    })

    seed_tracked_branch(auth_staging_impl, %{
      repo_uri: "github.com/acai-sh/auth-service",
      branch_name: "develop",
      last_seen_commit: "b2c3d4e5f6a7"
    })

    :ok
  end

  defp seed_tracked_branch(implementation, attrs) do
    defaults = %{
      repo_uri: "github.com/example/repo",
      branch_name: "main",
      last_seen_commit: "def123",
      implementation_id: implementation.id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from b in TrackedBranch,
          where: b.implementation_id == ^implementation.id,
          where: b.repo_uri == ^attrs.repo_uri
      )

    if existing do
      IO.puts(
        "Tracked branch already exists: #{attrs.repo_uri} for implementation #{implementation.name}"
      )

      existing
    else
      {:ok, branch} = Repo.insert(TrackedBranch.changeset(%TrackedBranch{}, attrs))
      IO.puts("Created tracked branch: #{branch.repo_uri}/#{branch.branch_name}")
      branch
    end
  end

  # ---------------------------------------------------------------------------
  # SpecImplState Seeding
  # ---------------------------------------------------------------------------

  # data-model.SPEC_IMPL_STATES
  defp seed_spec_impl_states([auth_spec, billing_spec | _], [
         auth_prod_impl,
         auth_staging_impl,
         billing_prod_impl | _
       ]) do
    IO.puts("\n=== Seeding SpecImplStates ===")

    # data-model.SPEC_IMPL_STATES.4: Store requirement states as JSONB
    now = DateTime.utc_now() |> DateTime.to_iso8601()

    seed_spec_impl_state(auth_spec, auth_prod_impl, %{
      states: %{
        "user-auth.LOGIN.1" => %{
          "status" => "completed",
          "comment" => "Implemented and tested",
          "updated_at" => now
        },
        "user-auth.LOGIN.1-1" => %{"status" => "completed", "updated_at" => now},
        "user-auth.LOGIN.2" => %{
          "status" => "in_progress",
          "comment" => "Rate limiting logic in review",
          "updated_at" => now
        },
        "user-auth.SESSION.1" => %{"status" => "completed", "updated_at" => now},
        "user-auth.SESSION.2" => %{"status" => "pending", "updated_at" => now}
      }
    })

    seed_spec_impl_state(auth_spec, auth_staging_impl, %{
      states: %{
        "user-auth.LOGIN.1" => %{"status" => "completed", "updated_at" => now},
        "user-auth.LOGIN.1-1" => %{"status" => "completed", "updated_at" => now},
        "user-auth.LOGIN.2" => %{"status" => "completed", "updated_at" => now},
        "user-auth.SESSION.1" => %{"status" => "completed", "updated_at" => now},
        "user-auth.SESSION.2" => %{"status" => "completed", "updated_at" => now}
      }
    })

    seed_spec_impl_state(billing_spec, billing_prod_impl, %{
      states: %{
        "subscription-management.BILLING.1" => %{"status" => "completed", "updated_at" => now},
        "subscription-management.BILLING.2" => %{"status" => "completed", "updated_at" => now},
        "subscription-management.BILLING.3" => %{
          "status" => "blocked",
          "comment" => "Waiting for Stripe integration",
          "updated_at" => now
        }
      }
    })

    :ok
  end

  # data-model.SPEC_IMPL_STATES.4: states stored as JSONB keyed by ACID
  defp seed_spec_impl_state(spec, implementation, attrs) do
    defaults = %{
      states: %{},
      spec_id: spec.id,
      implementation_id: implementation.id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from sis in SpecImplState,
          where: sis.spec_id == ^spec.id and sis.implementation_id == ^implementation.id
      )

    if existing do
      IO.puts(
        "SpecImplState already exists for spec #{spec.feature_name} and implementation #{implementation.name}"
      )

      existing
    else
      {:ok, state} = Repo.insert(SpecImplState.changeset(%SpecImplState{}, attrs))
      IO.puts("Created spec_impl_state for spec #{spec.feature_name}")
      state
    end
  end

  # ---------------------------------------------------------------------------
  # SpecImplRef Seeding
  # ---------------------------------------------------------------------------

  # data-model.SPEC_IMPL_REFS
  defp seed_spec_impl_refs([auth_spec, billing_spec | _], [
         auth_prod_impl,
         _,
         billing_prod_impl | _
       ]) do
    IO.puts("\n=== Seeding SpecImplRefs ===")

    # data-model.SPEC_IMPL_REFS.4: Store code references as JSONB
    seed_spec_impl_ref(auth_spec, auth_prod_impl, %{
      refs: %{
        "user-auth.LOGIN.1" => [
          %{
            "repo" => "github.com/acai-sh/auth-service",
            "path" => "lib/auth/login.ex:42",
            "loc" => "42:10",
            "is_test" => false
          },
          %{
            "repo" => "github.com/acai-sh/auth-service",
            "path" => "test/auth/login_test.ex:15",
            "loc" => "15:1",
            "is_test" => true
          }
        ],
        "user-auth.LOGIN.1-1" => [
          %{
            "repo" => "github.com/acai-sh/auth-service",
            "path" => "lib/auth/validation.ex:23",
            "loc" => "23:5",
            "is_test" => false
          }
        ],
        "user-auth.LOGIN.2" => [
          %{
            "repo" => "github.com/acai-sh/auth-service",
            "path" => "lib/auth/rate_limiter.ex:56",
            "loc" => "56:8",
            "is_test" => false
          },
          %{
            "repo" => "github.com/acai-sh/auth-service",
            "path" => "test/auth/rate_limiter_test.ex:30",
            "loc" => "30:3",
            "is_test" => true
          }
        ],
        "user-auth.SESSION.1" => [
          %{
            "repo" => "github.com/acai-sh/auth-service",
            "path" => "lib/auth/session.ex:89",
            "loc" => "89:12",
            "is_test" => false
          }
        ]
      },
      agent: "github-action",
      commit: "abc123def456",
      pushed_at: DateTime.utc_now()
    })

    seed_spec_impl_ref(billing_spec, billing_prod_impl, %{
      refs: %{
        "subscription-management.BILLING.1" => [
          %{
            "repo" => "github.com/acai-sh/billing-service",
            "path" => "lib/billing/subscription.ex:34",
            "loc" => "34:5",
            "is_test" => false
          }
        ],
        "subscription-management.BILLING.2" => [
          %{
            "repo" => "github.com/acai-sh/billing-service",
            "path" => "lib/billing/proration.ex:67",
            "loc" => "67:8",
            "is_test" => false
          },
          %{
            "repo" => "github.com/acai-sh/billing-service",
            "path" => "test/billing/proration_test.ex:45",
            "loc" => "45:1",
            "is_test" => true
          }
        ]
      },
      agent: "seeds",
      commit: "def789abc012",
      pushed_at: DateTime.utc_now()
    })

    :ok
  end

  # data-model.SPEC_IMPL_REFS.4: refs stored as JSONB keyed by ACID
  defp seed_spec_impl_ref(spec, implementation, attrs) do
    defaults = %{
      refs: %{},
      agent: "seeds",
      commit: "abc123",
      pushed_at: DateTime.utc_now(),
      spec_id: spec.id,
      implementation_id: implementation.id
    }

    attrs = Map.merge(defaults, attrs)

    existing =
      Repo.one(
        from sir in SpecImplRef,
          where: sir.spec_id == ^spec.id and sir.implementation_id == ^implementation.id
      )

    if existing do
      IO.puts(
        "SpecImplRef already exists for spec #{spec.feature_name} and implementation #{implementation.name}"
      )

      existing
    else
      {:ok, ref} = Repo.insert(SpecImplRef.changeset(%SpecImplRef{}, attrs))
      IO.puts("Created spec_impl_ref for spec #{spec.feature_name}")
      ref
    end
  end
end
