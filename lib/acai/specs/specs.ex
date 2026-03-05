defmodule Acai.Specs do
  @moduledoc """
  Context for specs, requirements, and code references.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Specs.{Spec, Requirement, CodeReference}
  alias Acai.Teams.Team
  alias Acai.Implementations.TrackedBranch

  # --- Specs ---

  def list_specs(_current_scope, %Team{} = team) do
    Repo.all(from s in Spec, where: s.team_id == ^team.id)
  end

  def get_spec!(id), do: Repo.get!(Spec, id)

  def create_spec(_current_scope, %Team{} = team, attrs) do
    %Spec{}
    |> Spec.changeset(attrs)
    |> Ecto.Changeset.put_change(:team_id, team.id)
    |> Repo.insert()
  end

  def update_spec(%Spec{} = spec, attrs) do
    spec
    |> Spec.changeset(attrs)
    |> Repo.update()
  end

  def change_spec(%Spec{} = spec, attrs \\ %{}) do
    Spec.changeset(spec, attrs)
  end

  # --- Requirements ---

  def list_requirements(%Spec{} = spec) do
    Repo.all(from r in Requirement, where: r.spec_id == ^spec.id)
  end

  # feature-view.IMPL_CARD.3
  @doc """
  Counts requirements for a spec.
  """
  def count_requirements(%Spec{} = spec) do
    Repo.one(
      from r in Requirement,
        where: r.spec_id == ^spec.id,
        select: count()
    )
  end

  def get_requirement!(id), do: Repo.get!(Requirement, id)

  def create_requirement(%Spec{} = spec, attrs) do
    %Requirement{}
    |> Requirement.changeset(attrs)
    |> Ecto.Changeset.put_change(:spec_id, spec.id)
    |> Repo.insert()
  end

  def update_requirement(%Requirement{} = requirement, attrs) do
    requirement
    |> Requirement.changeset(attrs)
    |> Repo.update()
  end

  def change_requirement(%Requirement{} = requirement, attrs \\ %{}) do
    Requirement.changeset(requirement, attrs)
  end

  # --- Code References ---

  def list_code_references(%Requirement{} = requirement) do
    Repo.all(from c in CodeReference, where: c.requirement_id == ^requirement.id)
  end

  def get_code_reference!(id), do: Repo.get!(CodeReference, id)

  def create_code_reference(
        %Requirement{} = requirement,
        %TrackedBranch{} = branch,
        attrs
      ) do
    %CodeReference{}
    |> CodeReference.changeset(attrs)
    |> Ecto.Changeset.put_change(:requirement_id, requirement.id)
    |> Ecto.Changeset.put_change(:branch_id, branch.id)
    |> Repo.insert()
  end

  @doc """
  Inserts or updates a code reference identified by (requirement_id, branch_id, path).

  On conflict the mutable tracking fields — last_seen_commit, last_seen_at, acid_string,
  repo_uri, and is_test — are updated in place, leaving id and inserted_at untouched.
  """
  def upsert_code_reference(
        %Requirement{} = requirement,
        %TrackedBranch{} = branch,
        attrs
      ) do
    %CodeReference{}
    |> CodeReference.changeset(attrs)
    |> Ecto.Changeset.put_change(:requirement_id, requirement.id)
    |> Ecto.Changeset.put_change(:branch_id, branch.id)
    |> Repo.insert(
      on_conflict:
        {:replace,
         [:last_seen_commit, :last_seen_at, :acid_string, :repo_uri, :is_test, :updated_at]},
      conflict_target: [:requirement_id, :branch_id, :path],
      returning: true
    )
  end

  def change_code_reference(%CodeReference{} = code_reference, attrs \\ %{}) do
    CodeReference.changeset(code_reference, attrs)
  end

  # nav.PANEL.3-2
  @doc """
  Returns a list of distinct feature_product values for a team.
  """
  def list_products_for_team(%Team{} = team) do
    Repo.all(
      from s in Spec,
        where: s.team_id == ^team.id,
        select: s.feature_product,
        distinct: true,
        order_by: s.feature_product
    )
  end

  # nav.PANEL.4-1
  @doc """
  Returns all specs for a team, grouped by product.
  """
  def list_specs_grouped_by_product(%Team{} = team) do
    specs = Repo.all(from s in Spec, where: s.team_id == ^team.id)

    Enum.group_by(specs, & &1.feature_product)
  end

  # nav.PANEL.5-3
  @doc """
  Gets a spec by feature_name for a team.
  """
  def get_spec_by_feature_name(%Team{} = team, feature_name) do
    Repo.one(
      from s in Spec,
        where: s.team_id == ^team.id and s.feature_name == ^feature_name
    )
  end

  # requirement-details.DRAWER.5-1
  @doc """
  Gets a requirement by ID with preloaded associations.
  """
  def get_requirement_with_refs!(id) do
    Repo.get!(Requirement, id)
  end

  # requirement-details.DRAWER.5-1
  # requirement-details.DRAWER.5-2
  @doc """
  Lists code references for a requirement, filtered by implementation's tracked branches.
  Returns references grouped by tracked_branch.

  Each reference has the branch association preloaded.
  """
  def list_code_references_for_requirement_and_implementation(
        %Requirement{} = requirement,
        %Acai.Implementations.Implementation{} = implementation
      ) do
    alias Acai.Implementations.TrackedBranch

    # Get all tracked branch IDs for this implementation
    tracked_branch_ids =
      Repo.all(
        from b in TrackedBranch,
          where: b.implementation_id == ^implementation.id,
          select: b.id
      )

    # Query code references for this requirement that belong to tracked branches
    refs =
      Repo.all(
        from ref in CodeReference,
          where: ref.requirement_id == ^requirement.id,
          where: ref.branch_id in ^tracked_branch_ids,
          preload: [:branch]
      )

    # Group by tracked_branch
    Enum.group_by(refs, & &1.branch)
  end

  # product-view.ROUTING.1
  @doc """
  Gets specs for a team by product name (case-insensitive).
  Returns the actual product name (from the database) and the list of specs.
  Returns nil if no matching product is found.
  """
  def get_specs_by_product_name(%Team{} = team, product_name) do
    # First, find the actual product name with case-insensitive matching
    actual_product =
      Repo.one(
        from s in Spec,
          where: s.team_id == ^team.id,
          where: fragment("lower(?)", s.feature_product) == ^String.downcase(product_name),
          select: s.feature_product,
          limit: 1
      )

    if actual_product do
      specs =
        Repo.all(
          from s in Spec,
            where: s.team_id == ^team.id and s.feature_product == ^actual_product
        )

      {actual_product, specs}
    else
      nil
    end
  end

  # feature-view.ROUTING.1
  @doc """
  Gets specs for a team by feature_name (case-insensitive).
  Returns the actual feature_name (from database) and the list of specs.
  Returns nil if no matching feature is found.
  """
  def get_specs_by_feature_name(%Team{} = team, feature_name) do
    # First, find the actual feature name with case-insensitive matching
    actual_feature_name =
      Repo.one(
        from s in Spec,
          where: s.team_id == ^team.id,
          where: fragment("lower(?)", s.feature_name) == ^String.downcase(feature_name),
          select: s.feature_name,
          limit: 1
      )

    if actual_feature_name do
      specs =
        Repo.all(
          from s in Spec,
            where: s.team_id == ^team.id and s.feature_name == ^actual_feature_name
        )

      {actual_feature_name, specs}
    else
      nil
    end
  end
end
