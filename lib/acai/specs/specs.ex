defmodule Acai.Specs do
  @moduledoc """
  Context for specs, feature_impl_states, and feature_impl_refs.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Specs.{Spec, FeatureImplState, FeatureBranchRef}
  alias Acai.Teams.Team
  alias Acai.Products.Product

  # --- Specs ---

  @doc """
  Lists all specs for a team.
  """
  def list_specs(_current_scope, %Team{} = team) do
    Repo.all(
      from s in Spec,
        join: p in Product,
        on: s.product_id == p.id,
        where: p.team_id == ^team.id
    )
  end

  @doc """
  Lists all specs for a product.
  """
  def list_specs_for_product(%Product{} = product) do
    Repo.all(from s in Spec, where: s.product_id == ^product.id)
  end

  @doc """
  Gets a spec by ID.
  """
  def get_spec!(id), do: Repo.get!(Spec, id)

  @doc """
  Creates a spec for a product.
  """
  def create_spec(_current_scope, %Product{} = product, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:product_id, product.id)

    %Spec{}
    |> Spec.changeset(attrs)
    |> Repo.insert()
  end

  # Deprecated: Legacy 4-arity wrapper for backward compatibility.
  # The team parameter is ignored. Please migrate to create_spec/3.
  def create_spec(current_scope, _team, %Product{} = product, attrs) do
    create_spec(current_scope, product, attrs)
  end

  @doc """
  Updates a spec.
  """
  def update_spec(%Spec{} = spec, attrs) do
    spec
    |> Spec.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for a spec.
  """
  def change_spec(%Spec{} = spec, attrs \\ %{}) do
    Spec.changeset(spec, attrs)
  end

  # --- Products Navigation ---

  @doc """
  Returns all specs for a team, grouped by product name.
  """
  def list_specs_grouped_by_product(%Team{} = team) do
    specs =
      Repo.all(
        from s in Spec,
          join: p in Product,
          on: s.product_id == p.id,
          where: p.team_id == ^team.id,
          preload: [:product]
      )

    Enum.group_by(specs, fn s -> s.product.name end)
  end

  @doc """
  Gets a spec by feature_name for a team.
  Returns the first matching spec if multiple exist (e.g. across different branches).
  """
  def get_spec_by_feature_name(%Team{} = team, feature_name) do
    Repo.all(
      from s in Spec,
        join: p in Product,
        on: s.product_id == p.id,
        where: p.team_id == ^team.id and s.feature_name == ^feature_name,
        limit: 1
    )
    |> List.first()
  end

  @doc """
  Gets specs for a team by feature_name (case-insensitive).
  Returns the actual feature_name (from database) and the list of specs.
  Returns nil if no matching feature is found.
  """
  def get_specs_by_feature_name(%Team{} = team, feature_name) do
    actual_feature_name =
      Repo.one(
        from s in Spec,
          join: p in Product,
          on: s.product_id == p.id,
          where: p.team_id == ^team.id,
          where: fragment("lower(?)", s.feature_name) == ^String.downcase(feature_name),
          select: s.feature_name,
          limit: 1
      )

    if actual_feature_name do
      specs =
        Repo.all(
          from s in Spec,
            join: p in Product,
            on: s.product_id == p.id,
            where: p.team_id == ^team.id and s.feature_name == ^actual_feature_name
        )

      # Ensure requirements field is loaded (it should be by default since it's JSONB)
      {actual_feature_name, specs}
    else
      nil
    end
  end

  @doc """
  Gets specs for a team by product name (case-insensitive).
  Returns the actual product name (from the database) and the list of specs.
  Returns nil if no matching product is found.
  """
  def get_specs_by_product_name(%Team{} = team, product_name) do
    product =
      Repo.one(
        from p in Product,
          where: p.team_id == ^team.id,
          where: fragment("lower(?)", p.name) == ^String.downcase(product_name),
          limit: 1
      )

    if product do
      specs =
        Repo.all(
          from s in Spec,
            where: s.product_id == ^product.id
        )

      {product.name, specs}
    else
      nil
    end
  end

  # --- FeatureImplStates ---

  @doc """
  Gets a feature_impl_state for a feature_name and implementation.
  Returns nil if not found.
  """
  def get_feature_impl_state(
        feature_name,
        %Acai.Implementations.Implementation{} = implementation
      ) do
    Repo.one(
      from fis in FeatureImplState,
        where: fis.feature_name == ^feature_name and fis.implementation_id == ^implementation.id
    )
  end

  @doc """
  Gets feature_impl_state for a feature_name, walking the parent chain if not found.
  Returns {state_row, source_impl_id} where source_impl_id indicates where the state came from.
  Returns {nil, nil} if not found anywhere in the chain.
  """
  def get_feature_impl_state_with_inheritance(
        feature_name,
        implementation_id,
        visited \\ MapSet.new()
      ) do
    # Prevent infinite loops in case of circular references
    if MapSet.member?(visited, implementation_id) do
      {nil, nil}
    else
      visited = MapSet.put(visited, implementation_id)

      case Repo.one(
             from fis in FeatureImplState,
               where:
                 fis.feature_name == ^feature_name and fis.implementation_id == ^implementation_id
           ) do
        nil ->
          # Not found, check parent implementation
          impl = Repo.get(Acai.Implementations.Implementation, implementation_id)

          if impl && impl.parent_implementation_id do
            get_feature_impl_state_with_inheritance(
              feature_name,
              impl.parent_implementation_id,
              visited
            )
          else
            {nil, nil}
          end

        state ->
          {state, implementation_id}
      end
    end
  end

  @doc """
  Creates a feature_impl_state for a feature_name and implementation.
  """
  def create_feature_impl_state(
        feature_name,
        %Acai.Implementations.Implementation{} = implementation,
        attrs
      ) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:feature_name, feature_name)
      |> Map.put(:implementation_id, implementation.id)

    %FeatureImplState{}
    |> FeatureImplState.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a feature_impl_state.
  """
  def update_feature_impl_state(%FeatureImplState{} = state, attrs) do
    state
    |> FeatureImplState.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Upserts a feature_impl_state by (feature_name, implementation_id).
  On conflict, replaces the states JSONB field.
  """
  def upsert_feature_impl_state(
        feature_name,
        %Acai.Implementations.Implementation{} = implementation,
        attrs
      ) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:feature_name, feature_name)
      |> Map.put(:implementation_id, implementation.id)

    %FeatureImplState{}
    |> FeatureImplState.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:states, :updated_at]},
      conflict_target: [:feature_name, :implementation_id],
      returning: true
    )
  end

  # --- FeatureImplState Batch Queries ---

  @doc """
  Batch gets feature_impl_state data for multiple feature_names and implementations.
  Returns a map of {feature_name, implementation_id} => %{completed: count, total: count}.

  This is used for building the feature × implementation matrix where each cell
  shows completion percentage.
  """
  def batch_get_feature_impl_completion(feature_names, implementations)
      when is_list(feature_names) and is_list(implementations) do
    impl_ids = Enum.map(implementations, & &1.id)

    # Fetch all feature_impl_states for the given feature_names and implementations
    states =
      Repo.all(
        from fis in FeatureImplState,
          where: fis.feature_name in ^feature_names and fis.implementation_id in ^impl_ids,
          select: {fis.feature_name, fis.implementation_id, fis.states}
      )

    # Build a map of {feature_name, impl_id} => completion data
    # feature-view.MAIN.3: Both completed and accepted count toward completion
    states
    |> Enum.map(fn {feature_name, impl_id, state_map} ->
      completed_count =
        Enum.count(state_map, fn {_acid, attrs} ->
          attrs["status"] in ["completed", "accepted"]
        end)

      total_count = map_size(state_map)

      {{feature_name, impl_id}, %{completed: completed_count, total: total_count}}
    end)
    |> Map.new()
  end

  @doc """
  Batch gets completion data for multiple specs and implementations.
  Returns a map of {spec_id, implementation_id} => %{completed: count, total: count}.

  Although states are stored by feature_name, completion for a specific spec is
  computed by filtering the feature state bucket down to that spec's ACIDs.
  """
  def batch_get_spec_impl_completion(specs, implementations)
      when is_list(specs) and is_list(implementations) do
    impl_ids = Enum.map(implementations, & &1.id)
    feature_names = specs |> Enum.map(& &1.feature_name) |> Enum.uniq()

    states_by_feature_impl =
      Repo.all(
        from fis in FeatureImplState,
          where: fis.feature_name in ^feature_names and fis.implementation_id in ^impl_ids,
          select: {{fis.feature_name, fis.implementation_id}, fis.states}
      )
      |> Map.new()

    for spec <- specs,
        implementation <- implementations,
        into: %{} do
      relevant_states =
        Map.get(states_by_feature_impl, {spec.feature_name, implementation.id}, %{})

      spec_acids = Map.keys(spec.requirements)

      completed_count =
        Enum.count(spec_acids, fn acid ->
          case relevant_states[acid] do
            %{"status" => status} when status in ["completed", "accepted"] -> true
            _ -> false
          end
        end)

      {{spec.id, implementation.id},
       %{completed: completed_count, total: map_size(spec.requirements)}}
    end
  end

  # --- FeatureBranchRefs (Branch-scoped refs) ---

  alias Acai.Implementations.{Branch, Implementation}

  @doc """
  Gets a feature_branch_ref for a feature_name and branch.
  Returns nil if not found.

  ACIDs:
  - data-model.FEATURE_BRANCH_REFS.2: branch_id FK
  - data-model.FEATURE_BRANCH_REFS.3: feature_name
  - data-model.FEATURE_BRANCH_REFS.8: Unique on (branch_id, feature_name)
  """
  def get_feature_branch_ref(feature_name, %Branch{} = branch) do
    Repo.one(
      from fbr in FeatureBranchRef,
        where: fbr.feature_name == ^feature_name and fbr.branch_id == ^branch.id
    )
  end

  @doc """
  Creates a feature_branch_ref for a feature_name and branch.

  ACID: data-model.FEATURE_BRANCH_REFS.4: refs JSONB format
  """
  def create_feature_branch_ref(feature_name, %Branch{} = branch, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:feature_name, feature_name)
      |> Map.put(:branch_id, branch.id)

    %FeatureBranchRef{}
    |> FeatureBranchRef.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a feature_branch_ref.
  """
  def update_feature_branch_ref(%FeatureBranchRef{} = ref, attrs) do
    ref
    |> FeatureBranchRef.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Upserts a feature_branch_ref by (feature_name, branch_id).
  On conflict, replaces the refs, commit, and pushed_at fields.

  ACIDs:
  - data-model.SPEC_IDENTITY.1: Spec id is stable across updates on same (branch_id, feature_name)
  - data-model.SPEC_IDENTITY.2: Pushing updated feature.yaml updates existing spec row
  - data-model.SPEC_IDENTITY.4: Version changes update spec row but don't create new spec
  """
  def upsert_feature_branch_ref(feature_name, %Branch{} = branch, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:feature_name, feature_name)
      |> Map.put(:branch_id, branch.id)

    %FeatureBranchRef{}
    |> FeatureBranchRef.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:refs, :commit, :pushed_at, :updated_at]},
      conflict_target: [:feature_name, :branch_id],
      returning: true
    )
  end

  # --- Legacy API (backwards compatibility with Implementation-based API) ---
  # These functions delegate to the new branch-scoped behavior

  @doc """
  Gets a feature_impl_state for a spec and implementation.
  Extracts feature_name from the spec.
  """
  def get_spec_impl_state(%Spec{} = spec, %Implementation{} = implementation) do
    get_feature_impl_state(spec.feature_name, implementation)
  end

  @doc """
  Creates or merges a feature_impl_state for a spec and implementation.
  Extracts feature_name from the spec.
  """
  def create_spec_impl_state(
        %Spec{} = spec,
        %Implementation{} = implementation,
        attrs
      ) do
    attrs = Map.new(attrs)

    case get_feature_impl_state(spec.feature_name, implementation) do
      nil ->
        create_feature_impl_state(spec.feature_name, implementation, attrs)

      %FeatureImplState{} = existing_state ->
        merged_states = Map.merge(existing_state.states || %{}, Map.get(attrs, :states, %{}))
        update_feature_impl_state(existing_state, Map.put(attrs, :states, merged_states))
    end
  end

  @doc """
  Updates a feature_impl_state.
  """
  def update_spec_impl_state(%FeatureImplState{} = state, attrs) do
    update_feature_impl_state(state, attrs)
  end

  @doc """
  Upserts a feature_impl_state by spec and implementation.
  Extracts feature_name from the spec.
  """
  def upsert_spec_impl_state(
        %Spec{} = spec,
        %Implementation{} = implementation,
        attrs
      ) do
    upsert_feature_impl_state(spec.feature_name, implementation, attrs)
  end

  @doc """
  Legacy: Gets refs for a spec and implementation.
  Now delegates to Implementations.count_refs_for_implementation/2.

  ACIDs:
  - feature-impl-view.MAIN.4: Refs column shows total refs across tracked branches
  - feature-impl-view.INHERITANCE.3: Refs aggregated from tracked branches
  """
  def get_spec_impl_ref(%Spec{} = spec, %Implementation{} = implementation) do
    # Return a pseudo-ref structure for backwards compatibility
    # The UI now uses Implementations.count_refs_for_implementation/2 directly
    ref_counts =
      Acai.Implementations.count_refs_for_implementation(spec.feature_name, implementation.id)

    # Return a map that mimics the old FeatureImplRef structure
    %{
      refs: %{},
      is_inherited: ref_counts.is_inherited,
      total_refs: ref_counts.total_refs,
      total_tests: ref_counts.total_tests
    }
  end

  @doc """
  Legacy: Creates refs for a spec and implementation.
  Now creates branch-scoped refs instead.

  ACID: data-model.INHERITANCE.8: Create refs on tracked branches
  """
  def create_spec_impl_ref(
        %Spec{} = spec,
        %Implementation{} = implementation,
        attrs
      ) do
    attrs = Map.new(attrs)

    # Create refs on all tracked branches for this implementation
    branch_ids = Acai.Implementations.get_tracked_branch_ids(implementation)

    branches = Repo.all(from b in Branch, where: b.id in ^branch_ids)

    Enum.each(branches, fn branch ->
      case get_feature_branch_ref(spec.feature_name, branch) do
        nil ->
          create_feature_branch_ref(spec.feature_name, branch, attrs)

        existing_ref ->
          merged_refs = Map.merge(existing_ref.refs || %{}, Map.get(attrs, :refs, %{}))
          update_feature_branch_ref(existing_ref, Map.put(attrs, :refs, merged_refs))
      end
    end)

    {:ok, %{}}
  end

  @doc """
  Legacy: Updates refs.
  """
  def update_spec_impl_ref(_ref, _attrs) do
    # No-op for backwards compatibility - refs are now branch-scoped
    {:ok, %{}}
  end

  @doc """
  Legacy: Upserts refs for a spec and implementation.
  Now upserts branch-scoped refs on tracked branches.
  """
  def upsert_spec_impl_ref(
        %Spec{} = spec,
        %Implementation{} = implementation,
        attrs
      ) do
    attrs = Map.new(attrs)

    # Upsert refs on all tracked branches for this implementation
    branch_ids = Acai.Implementations.get_tracked_branch_ids(implementation)
    branches = Repo.all(from b in Branch, where: b.id in ^branch_ids)

    Enum.each(branches, fn branch ->
      upsert_feature_branch_ref(spec.feature_name, branch, attrs)
    end)

    {:ok, %{}}
  end
end
