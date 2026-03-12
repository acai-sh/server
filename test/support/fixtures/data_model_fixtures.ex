defmodule Acai.DataModelFixtures do
  @moduledoc """
  Test helpers for creating entities across the DATA feature contexts.
  """

  alias Acai.Repo
  alias Acai.Teams.{Team, UserTeamRole, AccessToken}
  alias Acai.Products.Product
  alias Acai.Specs.{Spec, FeatureImplState, FeatureImplRef}
  alias Acai.Implementations.{Implementation, Branch, TrackedBranch}

  def unique_team_name, do: "team-#{System.unique_integer([:positive])}"
  def unique_product_name, do: "product-#{System.unique_integer([:positive])}"
  def unique_feature_name, do: "feature-#{System.unique_integer([:positive])}"

  def team_fixture(attrs \\ %{}) do
    {:ok, team} =
      attrs
      |> Enum.into(%{name: unique_team_name()})
      |> then(&Team.changeset(%Team{}, &1))
      |> Repo.insert()

    team
  end

  def user_team_role_fixture(team, user, attrs \\ %{}) do
    {:ok, role} =
      attrs
      |> Enum.into(%{title: "readonly"})
      |> then(&UserTeamRole.changeset(%UserTeamRole{}, &1))
      |> Ecto.Changeset.put_change(:team_id, team.id)
      |> Ecto.Changeset.put_change(:user_id, user.id)
      |> Repo.insert()

    role
  end

  def access_token_fixture(team, user, attrs \\ %{}) do
    {:ok, token} =
      attrs
      |> Enum.into(%{
        name: "Test Token",
        token_hash: "hash-#{System.unique_integer([:positive])}",
        token_prefix: "at_test",
        scopes: [
          "specs:read",
          "specs:write",
          "states:read",
          "states:write",
          "refs:read",
          "refs:write",
          "impls:read",
          "impls:write",
          "team:read"
        ]
      })
      |> then(&AccessToken.changeset(%AccessToken{}, &1))
      |> Ecto.Changeset.put_change(:team_id, team.id)
      |> Ecto.Changeset.put_change(:user_id, user.id)
      |> Repo.insert()

    token
  end

  def product_fixture(team, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        name: unique_product_name(),
        description: "Test product description",
        is_active: true
      })
      |> Map.put(:team_id, team.id)

    {:ok, product} =
      Product.changeset(%Product{}, attrs)
      |> Repo.insert()

    # Reload to ensure all fields are populated
    Repo.get!(Product, product.id)
  end

  def unique_branch_name, do: "branch-#{System.unique_integer([:positive])}"

  def branch_fixture(attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        repo_uri: "github.com/acai-sh/server",
        branch_name: unique_branch_name(),
        last_seen_commit: "abc123"
      })

    {:ok, branch} =
      Branch.changeset(%Branch{}, attrs)
      |> Repo.insert()

    branch
  end

  def spec_fixture(product, attrs \\ %{}) do
    # Create a branch if not provided
    branch = attrs[:branch] || attrs["branch"] || branch_fixture()

    attrs =
      attrs
      |> Enum.into(%{
        path: "features/example/feature.yaml",
        last_seen_commit: "abc123",
        parsed_at: DateTime.utc_now(:second),
        feature_name: unique_feature_name(),
        feature_description: "An example feature",
        feature_version: "1.0.0",
        raw_content: "feature:\n  name: example",
        requirements: %{}
      })
      |> Map.put(:product_id, product.id)
      |> Map.put(:branch_id, branch.id)

    {:ok, spec} =
      Spec.changeset(%Spec{}, attrs)
      |> Repo.insert()

    spec
  end

  def implementation_fixture(product, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        name: "Production",
        description: "Main production environment",
        is_active: true
      })
      |> Map.put(:product_id, product.id)
      |> Map.put(:team_id, product.team_id)

    {:ok, impl} =
      Implementation.changeset(%Implementation{}, attrs)
      |> Repo.insert()

    impl
  end

  def tracked_branch_fixture(implementation, attrs \\ %{}) do
    # Convert keyword list to map if needed
    attrs = Enum.into(attrs, %{})

    # Create a branch if not provided
    branch = attrs[:branch] || attrs["branch"]

    branch =
      branch ||
        branch_fixture(%{
          repo_uri: attrs[:repo_uri] || attrs["repo_uri"] || "github.com/acai-sh/server",
          branch_name: attrs[:branch_name] || attrs["branch_name"] || "main",
          last_seen_commit:
            attrs[:last_seen_commit] || attrs["last_seen_commit"] || "abc123def456"
        })

    attrs =
      attrs
      |> Enum.into(%{
        repo_uri: branch.repo_uri
      })
      |> Map.put(:implementation_id, implementation.id)
      |> Map.put(:branch_id, branch.id)
      |> Map.drop([
        :branch,
        "branch",
        :branch_name,
        "branch_name",
        :last_seen_commit,
        "last_seen_commit"
      ])

    {:ok, tracked_branch} =
      TrackedBranch.changeset(%TrackedBranch{}, attrs)
      |> Repo.insert()

    tracked_branch
  end

  def spec_impl_state_fixture(spec, implementation, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        states: %{
          "test-feature.COMP.1" => %{
            "status" => "pending",
            "comment" => "Initial state",
            "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
          }
        }
      })
      |> Map.put(:feature_name, spec.feature_name)
      |> Map.put(:implementation_id, implementation.id)

    {:ok, state} =
      FeatureImplState.changeset(%FeatureImplState{}, attrs)
      |> Repo.insert()

    state
  end

  def spec_impl_ref_fixture(spec, implementation, attrs \\ %{}) do
    attrs =
      attrs
      |> Enum.into(%{
        refs: %{
          "test-feature.COMP.1" => [
            %{
              "repo" => "github.com/acai-sh/server",
              "path" => "lib/my_app/my_module.ex",
              "loc" => "42:10",
              "is_test" => false
            }
          ]
        },
        agent: "github-action",
        commit: "abc123def456",
        pushed_at: DateTime.utc_now()
      })
      |> Map.put(:feature_name, spec.feature_name)
      |> Map.put(:implementation_id, implementation.id)

    {:ok, ref} =
      FeatureImplRef.changeset(%FeatureImplRef{}, attrs)
      |> Repo.insert()

    ref
  end
end
