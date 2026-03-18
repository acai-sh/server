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
  Lists all unique feature names for a product.

  Returns a list of {feature_name, feature_name} tuples for dropdown options.

  ACIDs:
  - feature-view.MAIN.1: Load available features for dropdown selector
  """
  def list_features_for_product(%Product{} = product) do
    Repo.all(
      from s in Spec,
        where: s.product_id == ^product.id,
        select: {s.feature_name, s.feature_name},
        distinct: true,
        order_by: s.feature_name
    )
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
    get_feature_impl_state_with_inheritance_impl(feature_name, implementation_id, nil, visited)
  end

  # Internal implementation that tracks the original implementation ID for inheritance
  defp get_feature_impl_state_with_inheritance_impl(
         feature_name,
         implementation_id,
         original_impl_id,
         visited
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
            # Track the original implementation ID on first call
            orig_id = original_impl_id || implementation_id

            get_feature_impl_state_with_inheritance_impl(
              feature_name,
              impl.parent_implementation_id,
              orig_id,
              visited
            )
          else
            {nil, nil}
          end

        state ->
          # If we walked up the parent chain, return the original impl ID as source
          source_impl_id = if original_impl_id, do: implementation_id, else: nil
          {state, source_impl_id}
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
  Batch checks feature availability for multiple (feature_name, implementation) pairs.

  Returns a map of {feature_name, implementation_id} => boolean indicating whether
  the feature is available (resolvable) for that implementation.

  A feature is considered available if the implementation has or inherits a spec
  for the feature_name, scoped to the implementation's product.

  This uses a batched query approach to avoid N+1 patterns:
  1. Fetches all tracked branch IDs for all implementations in one query
  2. Fetches all matching specs for those branches AND product in one query
  3. Builds ancestry chains using pre-fetched parent data

  ACIDs:
  - product-view.MATRIX.7-1: Cells where implementation doesn't have/inherit feature are unavailable
  - product-view.MATRIX.8: Feature not in ancestor tree renders as n/a
  - product-view.ROUTING.2: Batched query strategy for all matrix data
  """
  def batch_check_feature_availability(feature_names, implementations)
      when is_list(feature_names) and is_list(implementations) do
    if feature_names == [] or implementations == [] do
      %{}
    else
      product_id = List.first(implementations).product_id

      # Batch 1: Get all implementations in this product to build parent chains
      # This includes inactive ones since we need to walk the full ancestry
      all_product_impls =
        Repo.all(
          from i in Acai.Implementations.Implementation,
            where: i.product_id == ^product_id,
            select: {i.id, i.parent_implementation_id}
        )
        |> Map.new(fn {id, parent_id} -> {id, parent_id} end)

      # Build a map of implementation_id => list of ancestor IDs (including self)
      ancestors_by_impl =
        Map.new(implementations, fn impl ->
          {impl.id, build_ancestor_chain_for_availability(impl.id, all_product_impls)}
        end)

      # Get all ancestor IDs (including self) to fetch their tracked branches
      all_ancestor_ids =
        ancestors_by_impl
        |> Map.values()
        |> List.flatten()
        |> Enum.uniq()

      # Batch 2: Get all tracked branch IDs for all implementations and their ancestors
      tracked_branches =
        Repo.all(
          from tb in Acai.Implementations.TrackedBranch,
            where: tb.implementation_id in ^all_ancestor_ids,
            select: {tb.implementation_id, tb.branch_id}
        )

      # Group branch_ids by implementation_id
      branch_ids_by_impl =
        Enum.reduce(tracked_branches, %{}, fn {impl_id, branch_id}, acc ->
          Map.update(acc, impl_id, MapSet.new([branch_id]), &MapSet.put(&1, branch_id))
        end)

      all_branch_ids =
        tracked_branches
        |> Enum.map(&elem(&1, 1))
        |> Enum.uniq()

      # Batch 3: Get all specs for these branches that match any of the feature names
      # AND belong to the same product (preserving same-product semantics as resolve_canonical_spec/3)
      # Grouped by feature_name => MapSet of branch_ids
      specs_by_feature =
        if all_branch_ids == [] do
          %{}
        else
          Repo.all(
            from s in Spec,
              where:
                s.branch_id in ^all_branch_ids and
                  s.feature_name in ^feature_names and
                  s.product_id == ^product_id,
              select: {s.feature_name, s.branch_id}
          )
          |> Enum.reduce(%{}, fn {feature_name, branch_id}, acc ->
            Map.update(acc, feature_name, MapSet.new([branch_id]), &MapSet.put(&1, branch_id))
          end)
        end

      # Now check availability for each (feature_name, implementation) pair
      for feature_name <- feature_names,
          implementation <- implementations,
          into: %{} do
        available? =
          has_feature_with_batch_data?(
            feature_name,
            implementation,
            branch_ids_by_impl,
            specs_by_feature,
            ancestors_by_impl
          )

        {{feature_name, implementation.id}, available?}
      end
    end
  end

  # Build the ancestor chain for an implementation (self + all parents)
  defp build_ancestor_chain_for_availability(impl_id, all_impls_map) do
    do_build_ancestor_chain_for_availability(impl_id, all_impls_map, MapSet.new())
  end

  defp do_build_ancestor_chain_for_availability(nil, _all_impls_map, visited),
    do: MapSet.to_list(visited)

  defp do_build_ancestor_chain_for_availability(impl_id, all_impls_map, visited) do
    if MapSet.member?(visited, impl_id) do
      # Circular reference detected
      MapSet.to_list(visited)
    else
      visited = MapSet.put(visited, impl_id)
      parent_id = Map.get(all_impls_map, impl_id)
      do_build_ancestor_chain_for_availability(parent_id, all_impls_map, visited)
    end
  end

  # Check if an implementation has or inherits a feature using pre-fetched data
  defp has_feature_with_batch_data?(
         feature_name,
         implementation,
         branch_ids_by_impl,
         specs_by_feature,
         ancestors_by_impl
       ) do
    # Get the spec branch IDs for this feature
    spec_branch_ids = Map.get(specs_by_feature, feature_name, MapSet.new())

    # If no specs exist for this feature, early return
    if MapSet.size(spec_branch_ids) == 0 do
      false
    else
      # Get all ancestors for this implementation (including self)
      ancestor_ids = Map.get(ancestors_by_impl, implementation.id, [])

      # Check if any ancestor has a tracked branch with the spec
      Enum.any?(ancestor_ids, fn ancestor_id ->
        ancestor_branch_ids = Map.get(branch_ids_by_impl, ancestor_id, MapSet.new())
        not MapSet.disjoint?(ancestor_branch_ids, spec_branch_ids)
      end)
    end
  end

  @doc """
  Batch gets completion data for multiple specs and implementations.
  Returns a map of {spec_id, implementation_id} => %{completed: count, total: count}.

  Although states are stored by feature_name, completion for a specific spec is
  computed by filtering the feature state bucket down to that spec's ACIDs.

  ACIDs:
  - product-view.MATRIX.3: Cells display completion percentage (completed/total)
  - product-view.MATRIX.3-1: Progress inherits from parent when local row doesn't exist
  - product-view.ROUTING.2: Single batched query for all data
  """
  def batch_get_spec_impl_completion(specs, implementations)
      when is_list(specs) and is_list(implementations) do
    if specs == [] or implementations == [] do
      %{}
    else
      product_id = List.first(implementations).product_id
      feature_names = specs |> Enum.map(& &1.feature_name) |> Enum.uniq()

      # Build ancestor chains for all implementations (includes self + parents)
      # product-view.ROUTING.2: Batch fetch all ancestry data in one query
      ancestor_chains = build_ancestor_chains_for_specs(implementations, product_id)

      # Collect all ancestor IDs to fetch states in one query
      all_impl_ids =
        ancestor_chains
        |> Map.values()
        |> List.flatten()
        |> Enum.uniq()

      # Batch fetch all states for all implementations and feature_names
      # product-view.ROUTING.2: Single query for all states
      raw_states =
        Repo.all(
          from fis in FeatureImplState,
            where: fis.feature_name in ^feature_names and fis.implementation_id in ^all_impl_ids,
            select: {fis.implementation_id, fis.feature_name, fis.states}
        )

      # Group states by {feature_name, implementation_id} for lookup
      # Only include rows where a feature_impl_states row EXISTS
      # product-view.MATRIX.3-1: Absence of row triggers inheritance, not empty states
      states_by_feature_impl =
        raw_states
        |> Enum.map(fn {impl_id, feature_name, states} ->
          {{feature_name, impl_id}, states}
        end)
        |> Map.new()

      # For each spec/implementation pair, find inherited states if needed
      for spec <- specs,
          implementation <- implementations,
          into: %{} do
        # Get ancestor chain for this implementation (self first, then parents)
        chain = Map.get(ancestor_chains, implementation.id, [implementation.id])

        # Find the first implementation in chain that has a feature_impl_states row
        # product-view.MATRIX.3-1: Inherit from nearest ancestor with local row
        relevant_states =
          find_inherited_feature_states(spec.feature_name, chain, states_by_feature_impl)

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
  end

  # Build ancestor chains for all implementations in one batch query
  # Returns a map of impl_id => [impl_id, parent_id, grandparent_id, ...]
  # product-view.ROUTING.2: Batch query for ancestry data
  defp build_ancestor_chains_for_specs(implementations, product_id) do
    # Get all implementations in this product to build parent chains
    all_product_impls =
      Repo.all(
        from i in Acai.Implementations.Implementation,
          where: i.product_id == ^product_id,
          select: {i.id, i.parent_implementation_id}
      )
      |> Map.new()

    # Build ancestor chain for each implementation
    Map.new(implementations, fn impl ->
      chain = build_ancestor_chain_ordered(impl.id, all_product_impls)
      {impl.id, chain}
    end)
  end

  # Build ancestor chain for a single implementation (self + all parents)
  # Returns list in order: [self_id, parent_id, grandparent_id, ...]
  defp build_ancestor_chain_ordered(impl_id, all_impls_map, visited \\ MapSet.new()) do
    do_build_ancestor_chain_ordered(impl_id, all_impls_map, visited, [])
  end

  defp do_build_ancestor_chain_ordered(nil, _all_impls_map, _visited, acc), do: acc

  defp do_build_ancestor_chain_ordered(impl_id, all_impls_map, visited, acc) do
    if MapSet.member?(visited, impl_id) do
      # Circular reference detected
      acc
    else
      visited = MapSet.put(visited, impl_id)
      parent_id = Map.get(all_impls_map, impl_id)
      # Add current impl to end of chain, then continue with parent
      do_build_ancestor_chain_ordered(parent_id, all_impls_map, visited, acc ++ [impl_id])
    end
  end

  # Find states for a feature, checking self first then ancestors
  # Returns states from the FIRST implementation in chain that has a feature_impl_states row
  # product-view.MATRIX.3-1: Absence of local row triggers inheritance
  # product-view.MATRIX.3-1: Empty states map is still a local row (returns 0%)
  defp find_inherited_feature_states(feature_name, chain, states_by_feature_impl) do
    Enum.reduce_while(chain, %{}, fn impl_id, _acc ->
      case Map.get(states_by_feature_impl, {feature_name, impl_id}) do
        nil ->
          # No feature_impl_states row at this level, continue to next ancestor
          {:cont, %{}}

        states ->
          # Found a row (even if empty), use these states and stop searching
          # product-view.MATRIX.3-1: Empty %{} is still a local row, don't inherit
          {:halt, states}
      end
    end)
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

  # --- Features for Implementation (Product-scoped) ---

  @doc """
  Lists all features accessible to an implementation, filtered to the current product.

  Features are determined by specs on the implementation's tracked branches or inherited
  from parent implementations. The results are filtered to only include specs belonging
  to the specified product, preventing cross-product feature leakage when branches are shared.

  Returns a list of {feature_name, feature_name} tuples for dropdown options.

  ACIDs:
  - feature-impl-view.ROUTING.4: feature_name scoped to implementation tracked branches
  - feature-impl-view.INHERITANCE.1: Recurse up parent chain if spec not found on tracked branches
  - feature-impl-view.CARDS.1-3
  """
  def list_features_for_implementation(%Implementation{} = implementation, %Product{} = product) do
    # feature-impl-view.CARDS.1-3
    # Get all spec IDs accessible to this implementation (tracked branches + inheritance)
    spec_ids = get_all_accessible_spec_ids(implementation.id)

    if spec_ids == [] do
      []
    else
      Repo.all(
        from s in Spec,
          where: s.id in ^spec_ids,
          where: s.product_id == ^product.id,
          select: {s.feature_name, s.feature_name},
          distinct: true,
          order_by: s.feature_name
      )
    end
  end

  # Get all spec IDs accessible to an implementation (tracked branches + inheritance)
  defp get_all_accessible_spec_ids(implementation_id, visited \\ MapSet.new()) do
    if MapSet.member?(visited, implementation_id) do
      []
    else
      visited = MapSet.put(visited, implementation_id)
      implementation = Repo.get(Acai.Implementations.Implementation, implementation_id)

      if is_nil(implementation) do
        []
      else
        # Get specs on tracked branches
        branch_ids =
          Repo.all(
            from tb in Acai.Implementations.TrackedBranch,
              where: tb.implementation_id == ^implementation.id,
              select: tb.branch_id
          )

        local_spec_ids =
          if branch_ids == [] do
            []
          else
            Repo.all(
              from s in Spec,
                where: s.branch_id in ^branch_ids,
                select: s.id
            )
          end

        # Recurse to parent
        parent_spec_ids =
          if implementation.parent_implementation_id do
            get_all_accessible_spec_ids(implementation.parent_implementation_id, visited)
          else
            []
          end

        Enum.uniq(local_spec_ids ++ parent_spec_ids)
      end
    end
  end

  # --- Feature Page Consolidated Loader ---

  @doc """
  Loads all data needed for the feature page in a single batched query path.

  Returns:
  - `{:ok, feature_page_data}` - All data needed for the feature page
  - `{:error, :feature_not_found}` - If no specs exist for the feature name

  The returned `feature_page_data` is a map containing:
  - `:feature_name` - The canonical feature name
  - `:feature_description` - Description from the first spec
  - `:product` - The product record
  - `:specs` - All specs for this feature
  - `:available_features` - {feature_name, feature_name} tuples for dropdown
  - `:implementations` - List of active implementations that resolve this feature
  - `:status_counts_by_impl` - Map of impl_id => %{status => count}
  - `:total_requirements` - Total requirement count across all specs

  ACIDs:
  - feature-view.ENG.1: Single query fetches all specs, implementations, and state counts
  - feature-view.MAIN.2: Only active implementations that can resolve the feature
  - feature-view.ENG.2: Respects inheritance semantics
  - feature-impl-view.INHERITANCE.1: Inherited specs resolved via batched ancestry lookup
  - feature-impl-view.ROUTING.4: Same-product scoping for shared branches
  """
  def load_feature_page_data(%Team{} = team, feature_name) do
    # Step 1: Get the canonical feature name and specs
    case get_specs_by_feature_name(team, feature_name) do
      nil ->
        {:error, :feature_not_found}

      {actual_feature_name, specs} ->
        # Step 2: Get product info (preload product on first spec)
        first_spec = List.first(specs) |> Repo.preload(:product)
        product = first_spec.product

        # Step 3: Get available features for dropdown
        available_features = list_features_for_product(product)

        # Step 4: Get active implementations with batched canonical resolution
        implementations =
          list_implementations_for_feature_batched(actual_feature_name, product)

        # Step 5: Preload product for each implementation
        implementations = Repo.preload(implementations, :product)

        # Step 6: Get status counts for all implementations in one batch (with inheritance)
        # feature-view.ENG.2: Respects inheritance semantics for state counts
        status_counts_by_impl =
          Acai.Implementations.batch_get_feature_impl_state_counts_with_inheritance(
            implementations,
            specs
          )

        # Step 7: Calculate total requirements (unique across all specs)
        # ACIDs should be consistent across specs for the same feature
        total_requirements =
          specs
          |> Enum.flat_map(fn spec -> Map.keys(spec.requirements) end)
          |> Enum.uniq()
          |> length()

        {:ok,
         %{
           feature_name: actual_feature_name,
           feature_description: first_spec.feature_description,
           product: product,
           specs: specs,
           available_features: available_features,
           implementations: implementations,
           status_counts_by_impl: status_counts_by_impl,
           total_requirements: total_requirements
         }}
    end
  end

  # --- Implementations for Feature (Batched Resolution) ---

  @doc """
  Lists all active implementations in a product that have a valid canonical spec for the given feature.

  Uses a batched query approach to avoid N+1 patterns:
  1. Fetches all active implementations for the product
  2. Preloads all product implementations to build ancestry chains
  3. Batch fetches tracked branches for all implementations and ancestors
  4. Batch fetches specs for those branches (scoped to product)
  5. Filters implementations that can resolve the feature

  ACIDs:
  - feature-view.ENG.1: Batched query approach - constant queries regardless of implementation count
  - feature-view.MAIN.2: Only active implementations that can resolve the feature
  - feature-view.ENG.2: Respects inheritance semantics
  - feature-impl-view.INHERITANCE.1: Recurse up parent chain via preloaded ancestry data
  - feature-impl-view.ROUTING.4: Same-product scoping for shared branches
  """
  def list_implementations_for_feature_batched(feature_name, %Product{} = product) do
    # Get all active implementations for the product
    implementations =
      Repo.all(
        from i in Acai.Implementations.Implementation,
          where: i.product_id == ^product.id and i.is_active == true,
          order_by: i.name
      )

    if implementations == [] do
      []
    else
      # Batch check which implementations can resolve the feature
      availability =
        batch_check_feature_availability([feature_name], implementations)

      # Filter to only implementations that can resolve the feature
      Enum.filter(implementations, fn impl ->
        availability[{feature_name, impl.id}] == true
      end)
    end
  end

  # --- Implementations for Feature (Canonical Resolution) ---

  @doc """
  Lists all active implementations in a product that have a valid canonical spec for the given feature.

  An implementation is considered "valid" for a feature if `resolve_canonical_spec/3` returns
  a spec for that (feature_name, implementation_id) pair. This includes:
  - Implementations with the spec on their tracked branches
  - Implementations that inherit the spec from a parent implementation

  Only active implementations (is_active: true) are returned.

  Returns a list of Implementation structs that can be used in dropdown selectors.

  WARNING: This function has N+1 query behavior. Use `list_implementations_for_feature_batched/2`
  for better performance.

  ACIDs:
  - feature-impl-view.INHERITANCE.1: Recurse up parent chain if spec not found on tracked branches
  - feature-impl-view.ROUTING.4: feature_name scoped to implementation tracked branches
  - feature-impl-view.CARDS.1-4
  - feature-view.MAIN.2: Only active implementations that can resolve the feature
  - feature-view.ENG.2: Respects inheritance semantics
  """
  def list_implementations_for_feature(feature_name, %Product{} = product) do
    # feature-view.MAIN.2
    # feature-view.ENG.2
    # Get all active implementations for the product
    implementations =
      Repo.all(
        from i in Acai.Implementations.Implementation,
          where: i.product_id == ^product.id and i.is_active == true,
          order_by: i.name
      )

    # Filter to only implementations that can resolve the feature
    Enum.filter(implementations, fn impl ->
      case resolve_canonical_spec(feature_name, impl.id) do
        {nil, nil} -> false
        {_spec, _source_info} -> true
      end
    end)
  end

  # --- Canonical Spec Resolution with Inheritance ---

  alias Acai.Implementations.{Implementation, TrackedBranch}

  @doc """
  Resolves the canonical spec for a feature_name and implementation.

  The resolution follows this order:
  1. Search for specs on the implementation's tracked branches (by branch_id)
     that also belong to the implementation's product
  2. If not found, recurse up the parent_implementation_id chain,
     but only consider specs that belong to the original implementation's product

  Returns {spec, source_info} where source_info is a map containing:
  - :is_inherited - boolean indicating if spec came from parent chain
  - :source_implementation_id - the implementation ID where spec was found (or nil if local)
  - :source_branch - the branch where spec was found (or nil)

  Returns {nil, nil} if no spec found anywhere in the ancestry, or if the only
  matching spec belongs to a different product than the implementation.

  ACIDs:
  - feature-impl-view.INHERITANCE.1: Recurse up parent chain if spec not found on tracked branches
  - feature-impl-view.ROUTING.4: feature_name scoped to implementation tracked branches
  - feature-impl-view.ROUTING.4: spec must belong to the same product as the implementation
  """
  def resolve_canonical_spec(feature_name, implementation_id, visited \\ MapSet.new()) do
    resolve_canonical_spec_with_product(feature_name, implementation_id, nil, visited)
  end

  # Internal implementation that carries the original product_id through recursion
  defp resolve_canonical_spec_with_product(
         feature_name,
         implementation_id,
         original_product_id,
         visited
       ) do
    # Prevent infinite loops in case of circular references
    if MapSet.member?(visited, implementation_id) do
      {nil, nil}
    else
      visited = MapSet.put(visited, implementation_id)
      implementation = Repo.get(Implementation, implementation_id)

      if is_nil(implementation) do
        {nil, nil}
      else
        # On the first call, capture the original implementation's product_id
        # This is the product that the spec must belong to for resolution to succeed
        product_id = original_product_id || implementation.product_id

        # Get tracked branch IDs for this implementation
        branch_ids =
          Repo.all(
            from tb in TrackedBranch,
              where: tb.implementation_id == ^implementation.id,
              select: tb.branch_id
          )

        # Search for spec on tracked branches first, scoped to the original product
        spec =
          if branch_ids != [] do
            Repo.one(
              from s in Spec,
                where:
                  s.feature_name == ^feature_name and
                    s.branch_id in ^branch_ids and
                    s.product_id == ^product_id,
                preload: [:product, :branch],
                limit: 1
            )
          else
            nil
          end

        if spec do
          # Found spec on this implementation's tracked branches
          # Only valid if the spec's product matches the original implementation's product
          source_info = %{
            is_inherited: original_product_id != nil,
            source_implementation_id:
              if(original_product_id != nil, do: implementation_id, else: nil),
            source_branch: spec.branch
          }

          {spec, source_info}
        else
          # Not found, check parent implementation
          if implementation.parent_implementation_id do
            {parent_spec, parent_source} =
              resolve_canonical_spec_with_product(
                feature_name,
                implementation.parent_implementation_id,
                product_id,
                visited
              )

            if parent_spec do
              # Found in parent chain - mark as inherited
              source_info = %{
                is_inherited: true,
                source_implementation_id:
                  parent_source.source_implementation_id ||
                    implementation.parent_implementation_id,
                source_branch: parent_source.source_branch
              }

              {parent_spec, source_info}
            else
              {nil, nil}
            end
          else
            {nil, nil}
          end
        end
      end
    end
  end
end
