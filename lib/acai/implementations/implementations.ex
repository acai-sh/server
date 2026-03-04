defmodule Acai.Implementations do
  @moduledoc """
  Context for implementations, tracked branches, and requirement statuses.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Implementations.{Implementation, TrackedBranch, RequirementStatus}
  alias Acai.Specs.{Spec, Requirement}

  # --- Implementations ---

  def list_implementations(%Spec{} = spec) do
    Repo.all(from i in Implementation, where: i.spec_id == ^spec.id)
  end

  def get_implementation!(id), do: Repo.get!(Implementation, id)

  def create_implementation(_current_scope, %Spec{} = spec, attrs) do
    %Implementation{}
    |> Implementation.changeset(attrs)
    |> Ecto.Changeset.put_change(:spec_id, spec.id)
    |> Ecto.Changeset.put_change(:team_id, spec.team_id)
    |> Repo.insert()
  end

  def update_implementation(%Implementation{} = implementation, attrs) do
    implementation
    |> Implementation.changeset(attrs)
    |> Repo.update()
  end

  def change_implementation(%Implementation{} = implementation, attrs \\ %{}) do
    Implementation.changeset(implementation, attrs)
  end

  # --- Tracked Branches ---

  def list_tracked_branches(%Implementation{} = implementation) do
    Repo.all(from b in TrackedBranch, where: b.implementation_id == ^implementation.id)
  end

  def get_tracked_branch!(id), do: Repo.get!(TrackedBranch, id)

  def create_tracked_branch(%Implementation{} = implementation, attrs) do
    %TrackedBranch{}
    |> TrackedBranch.changeset(attrs)
    |> Ecto.Changeset.put_change(:implementation_id, implementation.id)
    |> Repo.insert()
  end

  def change_tracked_branch(%TrackedBranch{} = tracked_branch, attrs \\ %{}) do
    TrackedBranch.changeset(tracked_branch, attrs)
  end

  # --- Requirement Statuses ---

  def list_requirement_statuses(%Implementation{} = implementation) do
    Repo.all(from rs in RequirementStatus, where: rs.implementation_id == ^implementation.id)
  end

  def get_requirement_status!(id), do: Repo.get!(RequirementStatus, id)

  def create_requirement_status(
        %Implementation{} = implementation,
        %Requirement{} = requirement,
        attrs
      ) do
    %RequirementStatus{}
    |> RequirementStatus.changeset(attrs)
    |> Ecto.Changeset.put_change(:implementation_id, implementation.id)
    |> Ecto.Changeset.put_change(:requirement_id, requirement.id)
    |> Repo.insert()
  end

  def update_requirement_status(%RequirementStatus{} = requirement_status, attrs) do
    requirement_status
    |> RequirementStatus.changeset(attrs)
    |> Repo.update()
  end

  def change_requirement_status(%RequirementStatus{} = requirement_status, attrs \\ %{}) do
    RequirementStatus.changeset(requirement_status, attrs)
  end
end
