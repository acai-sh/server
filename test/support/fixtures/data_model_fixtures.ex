defmodule Acai.DataModelFixtures do
  @moduledoc """
  Test helpers for creating entities across the DATA feature contexts.
  """

  alias Acai.Repo
  alias Acai.Teams.{Team, UserTeamRole, AccessToken}
  alias Acai.Specs.{Spec, Requirement, CodeReference}
  alias Acai.Implementations.{Implementation, TrackedBranch, RequirementStatus}
  alias Acai.Events.ActivityEvent

  def unique_team_name, do: "team-#{System.unique_integer([:positive])}"

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
        scopes: ["specs:read", "specs:write"]
      })
      |> then(&AccessToken.changeset(%AccessToken{}, &1))
      |> Ecto.Changeset.put_change(:team_id, team.id)
      |> Ecto.Changeset.put_change(:user_id, user.id)
      |> Repo.insert()

    token
  end

  def spec_fixture(team, attrs \\ %{}) do
    {:ok, spec} =
      attrs
      |> Enum.into(%{
        repo_uri: "github.com/acai-sh/server",
        branch_name: "main",
        path: "features/example/feature.yaml",
        last_seen_commit: "abc123",
        parsed_at: DateTime.utc_now(:second),
        feature_name: "example-feature",
        feature_product: "acai",
        feature_description: "An example feature"
      })
      |> then(&Spec.changeset(%Spec{}, &1))
      |> Ecto.Changeset.put_change(:team_id, team.id)
      |> Repo.insert()

    spec
  end

  def requirement_fixture(spec, attrs \\ %{}) do
    {:ok, req} =
      attrs
      |> Enum.into(%{
        group_key: "COMP",
        group_type: :COMPONENT,
        local_id: "1",
        definition: "Some requirement definition.",
        is_deprecated: false,
        feature_name: "example-feature",
        replaced_by: []
      })
      |> then(&Requirement.changeset(%Requirement{}, &1))
      |> Ecto.Changeset.put_change(:spec_id, spec.id)
      |> Repo.insert()

    # Reload to get the generated acid column
    Repo.get!(Requirement, req.id)
  end

  def code_reference_fixture(requirement, branch, attrs \\ %{}) do
    {:ok, ref} =
      attrs
      |> Enum.into(%{
        repo_uri: "github.com/acai-sh/server",
        last_seen_commit: "abc123",
        acid_string: "example-feature.COMP.1",
        path: "lib/my_app/my_module.ex:42",
        is_test: false
      })
      |> then(&CodeReference.changeset(%CodeReference{}, &1))
      |> Ecto.Changeset.put_change(:requirement_id, requirement.id)
      |> Ecto.Changeset.put_change(:branch_id, branch.id)
      |> Repo.insert()

    ref
  end

  def implementation_fixture(spec, attrs \\ %{}) do
    {:ok, impl} =
      attrs
      |> Enum.into(%{name: "Production", is_active: true})
      |> then(&Implementation.changeset(%Implementation{}, &1))
      |> Ecto.Changeset.put_change(:spec_id, spec.id)
      |> Ecto.Changeset.put_change(:team_id, spec.team_id)
      |> Repo.insert()

    impl
  end

  def tracked_branch_fixture(implementation, attrs \\ %{}) do
    {:ok, branch} =
      attrs
      |> Enum.into(%{
        repo_uri: "github.com/acai-sh/server",
        branch_name: "main"
      })
      |> then(&TrackedBranch.changeset(%TrackedBranch{}, &1))
      |> Ecto.Changeset.put_change(:implementation_id, implementation.id)
      |> Repo.insert()

    branch
  end

  def requirement_status_fixture(implementation, requirement, attrs \\ %{}) do
    {:ok, status} =
      attrs
      |> Enum.into(%{is_active: true, last_seen_commit: "abc123"})
      |> then(&RequirementStatus.changeset(%RequirementStatus{}, &1))
      |> Ecto.Changeset.put_change(:implementation_id, implementation.id)
      |> Ecto.Changeset.put_change(:requirement_id, requirement.id)
      |> Repo.insert()

    status
  end

  def activity_event_fixture(team, attrs \\ %{}) do
    {:ok, event} =
      attrs
      |> Enum.into(%{
        event_type: "spec.created",
        subject_type: "spec",
        subject_id: Acai.UUIDv7.autogenerate(),
        payload: %{"key" => "value"}
      })
      |> then(&ActivityEvent.changeset(%ActivityEvent{}, &1))
      |> Ecto.Changeset.put_change(:team_id, team.id)
      |> Repo.insert()

    event
  end
end
