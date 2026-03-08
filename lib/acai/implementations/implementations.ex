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

  # product-view.FEATURE_CARD.3
  @doc """
  Counts active implementations for a spec.
  """
  def count_active_implementations(%Spec{} = spec) do
    Repo.one(
      from i in Implementation,
        where: i.spec_id == ^spec.id and i.is_active == true,
        select: count()
    )
  end

  # product-view.PERFORMANCE.1
  @doc """
  Batch counts active implementations for a list of specs.
  Returns a map of spec_id => count.
  """
  def batch_count_active_implementations_for_specs(specs) when is_list(specs) do
    spec_ids = Enum.map(specs, & &1.id)

    Repo.all(
      from i in Implementation,
        where: i.spec_id in ^spec_ids and i.is_active == true,
        group_by: i.spec_id,
        select: {i.spec_id, count()}
    )
    |> Map.new()
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

  @doc """
  Builds a URL-safe slug for an implementation.

  Format: {sanitized_name}+{uuid_without_dashes}
  """
  def implementation_slug(%Implementation{} = implementation) do
    "#{sanitize_slug_part(implementation.name)}+#{uuid_without_dashes(implementation.id)}"
  end

  # nav.PANEL.5-3
  @doc """
  Gets an implementation by parsing the slug pattern: {impl_name}+{uuid_without_dashes}.
  Returns nil if not found or invalid format.
  """
  def get_implementation_by_slug(slug) when is_binary(slug) do
    case Regex.run(~r/\+([0-9a-fA-F]{32})$/, slug, capture: :all_but_first) do
      [uuid_part] ->
        case parse_uuid_without_dashes(uuid_part) do
          {:ok, uuid} -> Repo.get(Implementation, uuid)
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_uuid_without_dashes(uuid_string) when byte_size(uuid_string) == 32 do
    # UUID without dashes is 32 characters
    # Format: 8-4-4-4-12 (total 36 with dashes, 32 without)
    try do
      formatted_uuid =
        String.slice(uuid_string, 0..7) <>
          "-" <>
          String.slice(uuid_string, 8..11) <>
          "-" <>
          String.slice(uuid_string, 12..15) <>
          "-" <>
          String.slice(uuid_string, 16..19) <>
          "-" <>
          String.slice(uuid_string, 20..31)

      {:ok, formatted_uuid}
    rescue
      _ -> :error
    end
  end

  defp parse_uuid_without_dashes(_), do: :error

  defp sanitize_slug_part(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "implementation"
      slug -> slug
    end
  end

  defp uuid_without_dashes(id) do
    id
    |> to_string()
    |> String.replace("-", "")
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

  # feature-view.MAIN.3
  @doc """
  Lists all active implementations for a list of specs.
  """
  def list_active_implementations_for_specs(specs) when is_list(specs) do
    spec_ids = Enum.map(specs, & &1.id)

    Repo.all(
      from i in Implementation,
        where: i.spec_id in ^spec_ids and i.is_active == true
    )
  end

  # feature-view.IMPL_CARD.2
  @doc """
  Counts tracked branches for an implementation.
  """
  def count_tracked_branches(%Implementation{} = implementation) do
    Repo.one(
      from b in TrackedBranch,
        where: b.implementation_id == ^implementation.id,
        select: count()
    )
  end

  # feature-view.PERFORMANCE.1
  @doc """
  Batch counts tracked branches for a list of implementations.
  Returns a map of implementation_id => count.
  """
  def batch_count_tracked_branches(implementations) when is_list(implementations) do
    impl_ids = Enum.map(implementations, & &1.id)

    Repo.all(
      from b in TrackedBranch,
        where: b.implementation_id in ^impl_ids,
        group_by: b.implementation_id,
        select: {b.implementation_id, count()}
    )
    |> Map.new()
  end

  # feature-view.IMPL_CARD.4
  @doc """
  Gets requirement status counts for an implementation.
  Returns %{accepted: count, completed: count, null: count}
  """
  def get_requirement_status_counts(%Implementation{} = implementation, total_requirements) do
    # Count statuses that are not null
    status_counts =
      Repo.all(
        from rs in RequirementStatus,
          where: rs.implementation_id == ^implementation.id,
          group_by: rs.status,
          select: {rs.status, count()}
      )
      |> Map.new()

    accepted = Map.get(status_counts, "accepted", 0)
    completed = Map.get(status_counts, "completed", 0)

    # Null count = total requirements - (accepted + completed)
    # This includes requirements with no requirement_status row or status IS NULL
    null = max(total_requirements - accepted - completed, 0)

    %{accepted: accepted, completed: completed, null: null}
  end

  # feature-view.PERFORMANCE.1
  @doc """
  Batch gets requirement status counts for multiple implementations.
  Returns a map of implementation_id => %{accepted: count, completed: count, null: count}

  Takes a map of implementation_id => total_requirements for that implementation's spec.
  """
  def batch_get_requirement_status_counts(impl_requirements_map)
      when is_map(impl_requirements_map) do
    impl_ids = Map.keys(impl_requirements_map)

    status_counts =
      Repo.all(
        from rs in RequirementStatus,
          where: rs.implementation_id in ^impl_ids,
          group_by: [rs.implementation_id, rs.status],
          select: {rs.implementation_id, rs.status, count()}
      )

    grouped =
      status_counts
      |> Enum.group_by(fn {impl_id, _status, _count} -> impl_id end)
      |> Map.new(fn {impl_id, counts} ->
        status_map =
          counts
          |> Enum.map(fn {_, status, count} -> {status, count} end)
          |> Map.new()

        {impl_id, status_map}
      end)

    impl_ids
    |> Map.new(fn impl_id ->
      impl_statuses = Map.get(grouped, impl_id, %{})
      accepted = Map.get(impl_statuses, "accepted", 0)
      completed = Map.get(impl_statuses, "completed", 0)
      total = Map.get(impl_requirements_map, impl_id, 0)
      null = max(total - accepted - completed, 0)

      {impl_id, %{accepted: accepted, completed: completed, null: null}}
    end)
  end

  # requirement-details.DRAWER.4
  @doc """
  Gets the requirement_status for a specific requirement and implementation.
  Returns nil if no status exists.
  """
  def get_requirement_status(%Requirement{} = requirement, %Implementation{} = implementation) do
    Repo.one(
      from rs in RequirementStatus,
        where: rs.implementation_id == ^implementation.id,
        where: rs.requirement_id == ^requirement.id
    )
  end
end
