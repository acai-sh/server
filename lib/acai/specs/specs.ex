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

  # --- Spec Inheritance ---

  @doc """
  Gets a spec for a feature_name, walking the parent chain via tracked branches.
  Returns {spec, source_impl_id} where source_impl_id indicates where the spec was found.
  Returns {nil, nil} if not found anywhere in the chain.

  ## Inheritance Rules

  - Checks the implementation's tracked branches first for a matching spec.
  - If not found, walks up the parent_implementation_id chain.
  - Child specs take precedence over parent specs (data-model.INHERITANCE.3).
  """
  def get_spec_for_feature_with_inheritance(
        feature_name,
        implementation_id,
        visited \\ MapSet.new()
      ) do
    # data-model.INHERITANCE.1
    # Prevent infinite loops in case of circular references
    if MapSet.member?(visited, implementation_id) do
      {nil, nil}
    else
      visited = MapSet.put(visited, implementation_id)

      # Get tracked branch IDs for this implementation
      branch_ids =
        Repo.all(
          from tb in Acai.Implementations.TrackedBranch,
            where: tb.implementation_id == ^implementation_id,
            select: tb.branch_id
        )

      # Look for a spec on any of these branches with matching feature_name
      case branch_ids do
        [] ->
          # No tracked branches, walk up the parent chain
          check_parent_for_spec(feature_name, implementation_id, visited)

        _ ->
          case Repo.one(
                 from s in Spec,
                   where: s.feature_name == ^feature_name and s.branch_id in ^branch_ids,
                   limit: 1
               ) do
            nil ->
              # Not found on this implementation's branches, check parent
              check_parent_for_spec(feature_name, implementation_id, visited)

            spec ->
              # Found on this implementation
              # data-model.INHERITANCE.3: Child's spec takes precedence
              {spec, implementation_id}
          end
      end
    end
  end

  defp check_parent_for_spec(feature_name, implementation_id, visited) do
    # data-model.INHERITANCE.2
    impl = Repo.get(Acai.Implementations.Implementation, implementation_id)

    if impl && impl.parent_implementation_id do
      # Recurse up the parent chain
      # data-model.INHERITANCE.5: Recursion depth is naturally limited by visited set
      get_spec_for_feature_with_inheritance(
        feature_name,
        impl.parent_implementation_id,
        visited
      )
    else
      {nil, nil}
    end
  end

  @doc """
  Returns an inheritance summary for a feature_name and implementation.

  Returns a map indicating whether spec, states, and refs are inherited:

      %{
        spec: %{inherited?: boolean, source_impl_id: id | nil},
        states: %{inherited?: boolean, source_impl_id: id | nil},
        refs: %{inherited?: boolean, source_impl_id: id | nil}
      }

  ## Inheritance Detection

  - If source_impl_id != queried implementation_id, the resource is inherited.
  - If source_impl_id is nil, the resource was not found anywhere in the chain.
  """
  def get_inheritance_summary(feature_name, implementation_id) do
    {spec, spec_source_impl_id} =
      get_spec_for_feature_with_inheritance(feature_name, implementation_id)

    {state, state_source_impl_id} =
      get_feature_impl_state_with_inheritance(feature_name, implementation_id)

    {ref, ref_source_impl_id} =
      get_feature_impl_ref_with_inheritance(feature_name, implementation_id)

    %{
      spec: %{
        found?: not is_nil(spec),
        inherited?: spec_source_impl_id != implementation_id,
        source_impl_id: spec_source_impl_id
      },
      states: %{
        found?: not is_nil(state),
        inherited?: state_source_impl_id != implementation_id,
        source_impl_id: state_source_impl_id
      },
      refs: %{
        found?: not is_nil(ref),
        inherited?: ref_source_impl_id != implementation_id,
        source_impl_id: ref_source_impl_id
      }
    }
  end

  @doc """
  Batch resolves specs for multiple feature_names and implementations with inheritance.

  Returns a map of {feature_name, impl_id} => spec | :not_found.

  This is used by the product-view matrix to determine which spec to display
  for each cell, respecting inheritance semantics.

  ## Algorithm

  1. Pre-compute parent chains for all implementations.
  2. Query all specs for all branch IDs across all chains.
  3. For each (feature_name, impl_id), resolve by checking the chain in order.
  """
  def batch_resolve_specs_for_implementations(feature_names, implementations)
      when is_list(feature_names) and is_list(implementations) do
    impl_ids = Enum.map(implementations, & &1.id)

    # Pre-compute parent chains for all implementations
    parent_chains =
      Map.new(impl_ids, fn impl_id ->
        {impl_id, Acai.Implementations.get_parent_chain(impl_id)}
      end)

    # Collect all implementation IDs across all chains
    all_impl_ids =
      parent_chains
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()

    # Get all tracked branches for all implementations in chains
    tracked_branches =
      Repo.all(
        from tb in Acai.Implementations.TrackedBranch,
          where: tb.implementation_id in ^all_impl_ids,
          select: {tb.implementation_id, tb.branch_id}
      )

    # Build map of impl_id => [branch_ids]
    branches_by_impl =
      Enum.reduce(tracked_branches, %{}, fn {impl_id, branch_id}, acc ->
        Map.update(acc, impl_id, [branch_id], &[branch_id | &1])
      end)

    # Collect all branch IDs
    all_branch_ids =
      branches_by_impl
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()

    # Query all relevant specs
    specs =
      Repo.all(
        from s in Spec,
          where: s.feature_name in ^feature_names and s.branch_id in ^all_branch_ids,
          select: {s.feature_name, s.branch_id, s}
      )

    # Build map of {feature_name, branch_id} => spec
    specs_by_feature_branch =
      Enum.reduce(specs, %{}, fn {feature_name, branch_id, spec}, acc ->
        Map.put(acc, {feature_name, branch_id}, spec)
      end)

    # Resolve specs for each (feature_name, impl_id)
    for feature_name <- feature_names,
        impl <- implementations,
        into: %{} do
      chain = Map.get(parent_chains, impl.id, [impl.id])

      result =
        find_spec_in_chain(feature_name, chain, branches_by_impl, specs_by_feature_branch)

      {{feature_name, impl.id}, result}
    end
  end

  defp find_spec_in_chain(feature_name, chain, branches_by_impl, specs_by_feature_branch) do
    Enum.find_value(chain, :not_found, fn impl_id ->
      branch_ids = Map.get(branches_by_impl, impl_id, [])

      Enum.find_value(branch_ids, fn branch_id ->
        Map.get(specs_by_feature_branch, {feature_name, branch_id})
      end)
    end)
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

  ## Options

  - `:inheritance` - When `true` (default), walks the parent chain to inherit states
    when not found directly on the implementation.
  """
  def batch_get_feature_impl_completion(feature_names, implementations, opts \\ [])
      when is_list(feature_names) and is_list(implementations) do
    inheritance? = Keyword.get(opts, :inheritance, true)

    if inheritance? do
      batch_get_feature_impl_completion_with_inheritance(feature_names, implementations)
    else
      batch_get_feature_impl_completion_without_inheritance(feature_names, implementations)
    end
  end

  defp batch_get_feature_impl_completion_without_inheritance(feature_names, implementations) do
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
    states_map =
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

    # Ensure all (feature_name, impl_id) pairs have a result (default to empty)
    for feature_name <- feature_names,
        impl <- implementations,
        into: %{} do
      result = Map.get(states_map, {feature_name, impl.id}, %{completed: 0, total: 0})
      {{feature_name, impl.id}, result}
    end
  end

  defp batch_get_feature_impl_completion_with_inheritance(feature_names, implementations) do
    impl_ids = Enum.map(implementations, & &1.id)

    # Pre-compute parent chains for all implementations
    parent_chains =
      Map.new(impl_ids, fn impl_id ->
        {impl_id, Acai.Implementations.get_parent_chain(impl_id)}
      end)

    # Collect all implementation IDs across all chains
    all_impl_ids =
      parent_chains
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()

    # Fetch all feature_impl_states for all implementations in chains
    all_states =
      Repo.all(
        from fis in FeatureImplState,
          where: fis.feature_name in ^feature_names and fis.implementation_id in ^all_impl_ids,
          select: {fis.feature_name, fis.implementation_id, fis.states}
      )

    # Build map of {feature_name, impl_id} => states
    states_by_feature_impl =
      Enum.reduce(all_states, %{}, fn {feature_name, impl_id, states}, acc ->
        Map.put(acc, {feature_name, impl_id}, states)
      end)

    # Resolve states for each (feature_name, impl_id) with inheritance
    for feature_name <- feature_names,
        impl <- implementations,
        into: %{} do
      chain = Map.get(parent_chains, impl.id, [impl.id])

      state_map = find_states_in_chain(feature_name, chain, states_by_feature_impl)

      completion_data =
        if state_map do
          completed_count =
            Enum.count(state_map, fn {_acid, attrs} ->
              attrs["status"] in ["completed", "accepted"]
            end)

          total_count = map_size(state_map)

          %{completed: completed_count, total: total_count}
        else
          %{completed: 0, total: 0}
        end

      {{feature_name, impl.id}, completion_data}
    end
  end

  defp find_states_in_chain(feature_name, chain, states_by_feature_impl) do
    # feature-impl-view.INHERITANCE.3: All-or-nothing semantics
    # If an impl has its own states row, use it entirely; otherwise inherit from parent
    Enum.find_value(chain, fn impl_id ->
      Map.get(states_by_feature_impl, {feature_name, impl_id})
    end)
  end

  @doc """
  Batch gets completion data for multiple specs and implementations.
  Returns a map of {spec_id, implementation_id} => %{completed: count, total: count}.

  Although states are stored by feature_name, completion for a specific spec is
  computed by filtering the feature state bucket down to that spec's ACIDs.

  ## Options

  - `:inheritance` - When `true` (default), walks the parent chain to inherit states
    when not found directly on the implementation.
  """
  def batch_get_spec_impl_completion(specs, implementations, opts \\ [])
      when is_list(specs) and is_list(implementations) do
    inheritance? = Keyword.get(opts, :inheritance, true)
    impl_ids = Enum.map(implementations, & &1.id)
    feature_names = specs |> Enum.map(& &1.feature_name) |> Enum.uniq()

    if inheritance? do
      batch_get_spec_impl_completion_with_inheritance(
        specs,
        implementations,
        feature_names,
        impl_ids
      )
    else
      batch_get_spec_impl_completion_without_inheritance(
        specs,
        implementations,
        feature_names,
        impl_ids
      )
    end
  end

  defp batch_get_spec_impl_completion_without_inheritance(
         specs,
         implementations,
         feature_names,
         impl_ids
       ) do
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

  defp batch_get_spec_impl_completion_with_inheritance(
         specs,
         implementations,
         feature_names,
         impl_ids
       ) do
    # Pre-compute parent chains for all implementations
    parent_chains =
      Map.new(impl_ids, fn impl_id ->
        {impl_id, Acai.Implementations.get_parent_chain(impl_id)}
      end)

    # Collect all implementation IDs across all chains
    all_impl_ids =
      parent_chains
      |> Map.values()
      |> List.flatten()
      |> Enum.uniq()

    # Fetch all feature_impl_states for all implementations in chains
    all_states =
      Repo.all(
        from fis in FeatureImplState,
          where: fis.feature_name in ^feature_names and fis.implementation_id in ^all_impl_ids,
          select: {{fis.feature_name, fis.implementation_id}, fis.states}
      )
      |> Map.new()

    for spec <- specs,
        implementation <- implementations,
        into: %{} do
      chain = Map.get(parent_chains, implementation.id, [implementation.id])

      # feature-impl-view.INHERITANCE.3: All-or-nothing semantics
      relevant_states = find_states_in_chain(spec.feature_name, chain, all_states) || %{}

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

  # Finds the first state in the chain that has data for the given feature_name
  defp find_states_in_chain(feature_name, chain, all_states) do
    Enum.reduce_while(chain, nil, fn impl_id, _acc ->
      case Map.get(all_states, {feature_name, impl_id}) do
        nil -> {:cont, nil}
        states -> {:halt, states}
      end
    end)
  end

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
  - data-model.SPEC_IDENTITY.1-1: Spec id is stable across updates on same (branch_id, feature_name)
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
