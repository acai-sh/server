defmodule Acai.Specs do
  @moduledoc """
  Context for specs and feature_impl_refs.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Specs.{Spec, FeatureBranchRef}
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

  @doc """
  Deletes a spec.

  feature-settings.DELETE_SPEC.5: On confirmation, the target spec for the current tracked branch is deleted
  """
  def delete_spec(%Spec{} = spec) do
    Repo.delete(spec)
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

  @doc """
  Deletes feature_branch_refs for a list of branch IDs and a feature_name.

  feature-settings.CLEAR_REFS.6: On confirmation, feature_branch_refs are cleared for all selected branches
  """
  def delete_feature_branch_refs_for_branches(branch_ids, feature_name)
      when is_list(branch_ids) do
    {count, _} =
      Repo.delete_all(
        from fbr in FeatureBranchRef,
          where: fbr.branch_id in ^branch_ids and fbr.feature_name == ^feature_name
      )

    {:ok, count}
  end

  @doc """
  Checks if local feature_branch_refs exist for any of the given branch IDs and feature_name.

  feature-settings.CLEAR_REFS.2_1: Button is disabled when no feature_branch_refs exist for any tracked branch
  """
  def local_feature_branch_refs_exist?(branch_ids, feature_name) when is_list(branch_ids) do
    if branch_ids == [] do
      false
    else
      count =
        Repo.one(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id in ^branch_ids and fbr.feature_name == ^feature_name,
            select: count()
        )

      count > 0
    end
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

  @doc """
  Loads the canonical feature context for one implementation.

  ACIDs:
  - feature-context.RESOLUTION.1: Resolves exactly one canonical spec
  - feature-context.RESOLUTION.2: Newest updated_at wins on local tracked branches
  - feature-context.RESOLUTION.3: Falls back to nearest ancestor with a local spec
   - feature-context.RESOLUTION.4: State-like data inherit from the nearest ancestor row
  - feature-context.RESOLUTION.5: Refs aggregate locally, then fall back to parent
   - feature-context.RESOLUTION.6: Empty local rows stop inheritance
  - feature-context.RESPONSE.1: Successful read returns a data payload
  """
  def get_feature_context(
        %Team{} = team,
        product_name,
        feature_name,
        implementation_name,
        opts \\ []
      ) do
    include_refs = Keyword.get(opts, :include_refs, false)
    include_deprecated = Keyword.get(opts, :include_deprecated, false)

    with {:ok, context} <-
           load_feature_context_context(team, product_name, implementation_name),
         {:ok, payload} <-
           build_feature_context_payload(context, feature_name, include_refs, include_deprecated) do
      {:ok, payload}
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      nil -> {:error, :not_found}
    end
  end

  @doc """
  Loads the summary worklist for all features visible to one implementation.

  ACIDs:
  - implementation-features.ENDPOINT.1: Read the implementation features worklist
  - implementation-features.DISCOVERY.1: Lists features that resolve for the selected implementation, including inherited features
  - implementation-features.DISCOVERY.2: Each feature is represented once using its canonical spec for that implementation
  - implementation-features.DISCOVERY.3: Newest updated_at wins on local tracked branches
   - implementation-features.DISCOVERY.4: Completion counts use resolved feature data for that implementation
  - implementation-features.DISCOVERY.5: Ref counts aggregate refs across tracked branches and fall back to the nearest ancestor implementation only when no refs exist locally
  - implementation-features.DISCOVERY.6: Status filters keep only features with at least one matching resolved ACID
  - implementation-features.DISCOVERY.7: changed_since_commit compares against the selected canonical spec
  - implementation-features.DISCOVERY.8: Ties on updated_at prefer the lexicographically smallest branch name
  - implementation-features.RESPONSE.1: Successful reads return a data payload
  - implementation-features.RESPONSE.2: Response includes product and implementation identifiers
  - implementation-features.RESPONSE.3: Features are returned in stable name order
  - implementation-features.RESPONSE.4: Feature entries include summary counts
  - implementation-features.RESPONSE.5: Feature entries include ref and local-source flags
  - implementation-features.RESPONSE.6: Feature entries include the canonical spec commit marker
  - implementation-features.RESPONSE.7: Feature entries include inheritance flags
  """
  def load_implementation_features(%Team{} = team, product_name, implementation_name, opts \\ []) do
    changed_since_commit = Keyword.get(opts, :changed_since_commit)

    with {:ok, context} <- load_feature_context_context(team, product_name, implementation_name) do
      feature_names =
        list_features_for_implementation(context.implementation, context.product)
        |> Enum.map(&elem(&1, 0))

      feature_candidates = load_implementation_feature_candidates(context, feature_names)

      features =
        feature_names
        |> Enum.map(fn feature_name ->
          build_implementation_feature_entry(
            feature_name,
            context,
            feature_candidates,
            changed_since_commit
          )
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.sort_by(& &1.feature_name)

      {:ok,
       %{
         product_name: context.product.name,
         implementation_name: context.implementation.name,
         implementation_id: context.implementation.id,
         features: features
       }}
    else
      {:error, :not_found} -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
      nil -> {:error, :not_found}
    end
  end

  # feature-context.RESOLUTION.1, feature-context.RESOLUTION.2, feature-context.RESOLUTION.3, feature-context.RESOLUTION.4, feature-context.RESOLUTION.5, feature-context.RESOLUTION.6
  # feature-context.RESPONSE.2, feature-context.RESPONSE.3, feature-context.RESPONSE.4, feature-context.RESPONSE.5
  defp build_feature_context_payload(
         context,
         feature_name,
         include_refs,
         include_deprecated
       ) do
    case resolve_canonical_spec_with_context(feature_name, context) do
      {nil, nil} ->
        {:error, :not_found}

      {spec, spec_source} ->
        {aggregated_refs, refs_source_impl_id} =
          get_aggregated_refs_with_context(feature_name, context)

        spec_source_payload =
          build_spec_source_payload(context, spec_source)

        refs_source_payload =
          build_refs_source_payload(context, aggregated_refs, refs_source_impl_id)

        acids =
          spec.requirements
          |> Enum.map(fn {acid, requirement} ->
            build_acid_entry(acid, requirement, aggregated_refs, include_refs)
          end)
          |> Enum.reject(fn acid_entry ->
            include_deprecated == false and Map.get(acid_entry, :deprecated, false)
          end)
          |> Enum.sort_by(& &1.acid)

        {:ok,
         %{
           product_name: context.product.name,
           feature_name: feature_name,
           implementation_name: context.implementation.name,
           implementation_id: context.implementation.id,
           spec_source: spec_source_payload,
           refs_source: refs_source_payload,
           acids: acids,
           warnings: []
         }}
    end
  end

  # implementation-features.DISCOVERY.1, implementation-features.DISCOVERY.2, implementation-features.DISCOVERY.3, implementation-features.DISCOVERY.4, implementation-features.DISCOVERY.5, implementation-features.DISCOVERY.6, implementation-features.DISCOVERY.7, implementation-features.DISCOVERY.8
  defp load_implementation_feature_candidates(context, feature_names) do
    %{
      specs_by_feature: load_implementation_feature_specs(context, feature_names),
      refs_by_feature: load_implementation_feature_refs(context, feature_names)
    }
  end

  defp load_implementation_feature_specs(context, feature_names) do
    if feature_names == [] or context.all_branch_ids == [] do
      %{}
    else
      Repo.all(
        from s in Spec,
          join: b in assoc(s, :branch),
          where:
            s.feature_name in ^feature_names and
              s.product_id == ^context.product.id and
              s.branch_id in ^context.all_branch_ids,
          order_by: [desc: s.updated_at, asc: b.branch_name, asc: s.id],
          preload: [:branch]
      )
      |> Enum.group_by(& &1.feature_name)
    end
  end

  defp load_implementation_feature_refs(context, feature_names) do
    if feature_names == [] or context.all_branch_ids == [] do
      %{}
    else
      Repo.all(
        from fbr in FeatureBranchRef,
          where:
            fbr.feature_name in ^feature_names and
              fbr.branch_id in ^context.all_branch_ids,
          select: {fbr.feature_name, fbr.branch_id, fbr.refs}
      )
      |> Enum.reduce(%{}, fn {feature_name, branch_id, refs}, acc ->
        Map.update(
          acc,
          feature_name,
          %{branch_id => refs || %{}},
          &Map.put(&1, branch_id, refs || %{})
        )
      end)
    end
  end

  # feature-context.RESOLUTION.1, feature-context.RESOLUTION.3, feature-context.RESOLUTION.4, feature-context.RESOLUTION.5, feature-context.RESPONSE.2
  defp load_feature_context_context(%Team{} = team, product_name, implementation_name) do
    with {:ok, product} <- Acai.Products.get_product_by_team_and_name(team, product_name),
         {:ok, implementation} <-
           Acai.Implementations.get_implementation_by_team_and_product_name(
             team,
             product,
             implementation_name
           ) do
      implementations = Acai.Implementations.list_implementations(product)
      implementations_by_id = Map.new(implementations, &{&1.id, &1})

      ancestor_chain = build_ancestor_chain(implementation.id, implementations_by_id)
      ancestor_ids = Enum.map(ancestor_chain, & &1.id)

      {branch_ids_by_impl, branches_by_impl, all_branch_ids} =
        load_branch_context(ancestor_ids)

      {:ok,
       %{
         product: product,
         implementation: implementation,
         implementations_by_id: implementations_by_id,
         ancestor_chain: ancestor_chain,
         ancestor_ids: ancestor_ids,
         branch_ids_by_impl: branch_ids_by_impl,
         branches_by_impl: branches_by_impl,
         all_branch_ids: all_branch_ids
       }}
    end
  end

  # implementation-features.DISCOVERY.2, implementation-features.DISCOVERY.3, implementation-features.DISCOVERY.8
  defp build_implementation_feature_entry(
         feature_name,
         context,
         feature_candidates,
         changed_since_commit
       ) do
    case resolve_canonical_spec_from_feature_specs(
           feature_name,
           context,
           Map.get(feature_candidates.specs_by_feature, feature_name, [])
         ) do
      {nil, nil} ->
        nil

      {spec, spec_source} ->
        {aggregated_refs, refs_source_impl_id} =
          get_aggregated_refs_from_feature_refs(
            feature_name,
            context,
            Map.get(feature_candidates.refs_by_feature, feature_name, %{})
          )

        if include_feature_in_worklist?(spec, changed_since_commit) do
          {refs_count, test_refs_count} = count_feature_refs(aggregated_refs)

          %{
            feature_name: feature_name,
            description: spec.feature_description,
            refs_count: refs_count,
            test_refs_count: test_refs_count,
            has_local_spec: not spec_source.is_inherited,
            spec_last_seen_commit: spec.last_seen_commit,
            refs_inherited: not is_nil(refs_source_impl_id)
          }
        else
          nil
        end
    end
  end

  defp resolve_canonical_spec_from_feature_specs(_feature_name, context, specs) do
    case specs do
      [] ->
        {nil, nil}

      _ ->
        resolve_canonical_spec_from_candidates(
          specs,
          context.ancestor_chain,
          context.branch_ids_by_impl,
          context.implementation.id
        )
    end
  end

  defp include_feature_in_worklist?(spec, changed_since_commit) do
    is_nil(changed_since_commit) or spec.last_seen_commit != changed_since_commit
  end

  defp count_feature_refs(aggregated_refs) do
    Enum.reduce(aggregated_refs, {0, 0}, fn {_branch, refs_map}, {refs_acc, tests_acc} ->
      Enum.reduce(refs_map, {refs_acc, tests_acc}, fn {_acid, ref_list}, {r_acc, t_acc} ->
        ref_count = Enum.count(ref_list, fn ref -> not Map.get(ref, "is_test", false) end)
        test_count = Enum.count(ref_list, fn ref -> Map.get(ref, "is_test", false) end)
        {r_acc + ref_count, t_acc + test_count}
      end)
    end)
  end

  defp build_ancestor_chain(implementation_id, implementations_by_id) do
    do_build_ancestor_chain(implementation_id, implementations_by_id, MapSet.new(), [])
  end

  defp do_build_ancestor_chain(nil, _implementations_by_id, _visited, acc), do: Enum.reverse(acc)

  defp do_build_ancestor_chain(implementation_id, implementations_by_id, visited, acc) do
    if MapSet.member?(visited, implementation_id) do
      Enum.reverse(acc)
    else
      visited = MapSet.put(visited, implementation_id)
      implementation = Map.get(implementations_by_id, implementation_id)

      if is_nil(implementation) do
        Enum.reverse(acc)
      else
        do_build_ancestor_chain(
          implementation.parent_implementation_id,
          implementations_by_id,
          visited,
          [implementation | acc]
        )
      end
    end
  end

  # feature-context.RESOLUTION.1, feature-context.RESOLUTION.3, feature-context.RESOLUTION.4, feature-context.RESOLUTION.5
  defp load_branch_context(implementation_ids) do
    if implementation_ids == [] do
      {%{}, %{}, []}
    else
      tracked_branches =
        Repo.all(
          from tb in Acai.Implementations.TrackedBranch,
            join: b in assoc(tb, :branch),
            where: tb.implementation_id in ^implementation_ids,
            select: {tb.implementation_id, b}
        )

      branch_ids_by_impl =
        Enum.reduce(tracked_branches, %{}, fn {impl_id, branch}, acc ->
          Map.update(acc, impl_id, MapSet.new([branch.id]), &MapSet.put(&1, branch.id))
        end)

      branches_by_impl =
        Enum.reduce(tracked_branches, %{}, fn {impl_id, branch}, acc ->
          Map.update(acc, impl_id, [branch], &[branch | &1])
        end)
        |> Map.new(fn {impl_id, branches} ->
          {impl_id, Enum.sort_by(branches, & &1.branch_name)}
        end)

      all_branch_ids =
        tracked_branches
        |> Enum.map(fn {_impl_id, branch} -> branch.id end)
        |> Enum.uniq()

      {branch_ids_by_impl, branches_by_impl, all_branch_ids}
    end
  end

  # feature-context.RESOLUTION.1, feature-context.RESOLUTION.2, feature-context.RESOLUTION.3, feature-context.RESOLUTION.8
  defp resolve_canonical_spec_with_context(feature_name, context) do
    case context.all_branch_ids do
      [] ->
        {nil, nil}

      _ ->
        specs =
          Repo.all(
            from s in Spec,
              join: b in assoc(s, :branch),
              where:
                s.feature_name == ^feature_name and
                  s.product_id == ^context.product.id and
                  s.branch_id in ^context.all_branch_ids,
              order_by: [desc: s.updated_at, asc: b.branch_name, asc: s.id],
              preload: [:branch]
          )

        resolve_canonical_spec_from_feature_specs(feature_name, context, specs)
    end
  end

  defp resolve_canonical_spec_from_candidates(
         specs,
         ancestor_chain,
         branch_ids_by_impl,
         implementation_id
       ) do
    Enum.reduce_while(ancestor_chain, {nil, nil}, fn implementation, _acc ->
      branch_ids = Map.get(branch_ids_by_impl, implementation.id, MapSet.new())

      case Enum.find(specs, fn spec -> MapSet.member?(branch_ids, spec.branch_id) end) do
        nil ->
          {:cont, {nil, nil}}

        spec ->
          source_impl_id =
            if implementation.id != implementation_id, do: implementation.id, else: nil

          branch_names =
            specs
            |> Enum.filter(fn candidate ->
              MapSet.member?(
                Map.get(branch_ids_by_impl, implementation.id, MapSet.new()),
                candidate.branch_id
              )
            end)
            |> Enum.map(& &1.branch.branch_name)
            |> Enum.uniq()
            |> Enum.sort()

          source_info = %{
            is_inherited: implementation.id != implementation_id,
            source_implementation_id: source_impl_id,
            source_branch: spec.branch,
            branch_names: branch_names
          }

          {:halt, {spec, source_info}}
      end
    end)
  end

  # feature-context.RESOLUTION.5
  defp get_aggregated_refs_with_context(feature_name, context) do
    case context.all_branch_ids do
      [] ->
        {[], nil}

      _ ->
        refs_by_branch_id =
          Repo.all(
            from fbr in FeatureBranchRef,
              join: b in assoc(fbr, :branch),
              where:
                fbr.feature_name == ^feature_name and
                  fbr.branch_id in ^context.all_branch_ids,
              preload: [:branch]
          )
          |> Map.new(fn ref -> {ref.branch_id, ref} end)

        get_aggregated_refs_from_feature_refs(feature_name, context, refs_by_branch_id)
    end
  end

  defp get_aggregated_refs_from_feature_refs(_feature_name, context, refs_by_branch_id) do
    if refs_by_branch_id == %{} do
      {[], nil}
    else
      Enum.reduce_while(context.ancestor_chain, {[], nil}, fn implementation, _acc ->
        branches = Map.get(context.branches_by_impl, implementation.id, [])

        aggregated_refs =
          branches
          |> Enum.flat_map(fn branch ->
            case Map.get(refs_by_branch_id, branch.id) do
              nil -> []
              %FeatureBranchRef{refs: refs} -> [{branch, refs || %{}}]
              refs when is_map(refs) -> [{branch, refs || %{}}]
            end
          end)

        case aggregated_refs do
          [] ->
            {:cont, {[], nil}}

          _ ->
            source_impl_id =
              if implementation.id == context.implementation.id,
                do: nil,
                else: implementation.id

            {:halt, {aggregated_refs, source_impl_id}}
        end
      end)
    end
  end

  defp build_spec_source_payload(context, spec_source) do
    source_impl_id = spec_source.source_implementation_id || context.implementation.id

    source_implementation =
      Map.get(context.implementations_by_id, source_impl_id, context.implementation)

    %{
      source_type: if(spec_source.is_inherited, do: "inherited", else: "local"),
      implementation_name: source_implementation && source_implementation.name,
      branch_names: Map.get(spec_source, :branch_names, [])
    }
  end

  defp build_refs_source_payload(context, aggregated_refs, refs_source_impl_id) do
    source_impl =
      cond do
        aggregated_refs == [] and is_nil(refs_source_impl_id) -> nil
        is_nil(refs_source_impl_id) -> context.implementation
        true -> Map.get(context.implementations_by_id, refs_source_impl_id)
      end

    %{
      source_type:
        cond do
          aggregated_refs == [] and is_nil(refs_source_impl_id) -> "none"
          is_nil(refs_source_impl_id) -> "local"
          true -> "inherited"
        end,
      implementation_name: source_impl && source_impl.name,
      branch_names:
        Enum.map(aggregated_refs, fn {branch, _refs} -> branch.branch_name end)
        |> Enum.uniq()
        |> Enum.sort()
    }
  end

  defp build_acid_entry(acid, requirement, aggregated_refs, include_refs) do
    acid_refs = Acai.Implementations.get_refs_for_acid(aggregated_refs, acid)

    ref_entries =
      if include_refs do
        Enum.flat_map(acid_refs, fn {branch, ref_list} ->
          Enum.map(ref_list, fn ref ->
            %{
              path: ref["path"],
              is_test: Map.get(ref, "is_test", false),
              repo_uri: branch.repo_uri,
              branch_name: branch.branch_name
            }
          end)
        end)
      else
        []
      end

    %{
      acid: acid,
      requirement: requirement["requirement"] || requirement[:requirement],
      note: requirement["note"] || requirement[:note],
      deprecated: Map.get(requirement, "deprecated", Map.get(requirement, :deprecated, false)),
      replaced_by: requirement["replaced_by"] || requirement[:replaced_by],
      refs_count:
        Enum.reduce(acid_refs, 0, fn {_branch, ref_list}, acc -> acc + length(ref_list) end),
      test_refs_count:
        Enum.reduce(acid_refs, 0, fn {_branch, ref_list}, acc ->
          acc + Enum.count(ref_list, fn ref -> Map.get(ref, "is_test", false) end)
        end)
    }
    |> maybe_put_refs(ref_entries, include_refs)
  end

  defp maybe_put_refs(acid_entry, refs, true), do: Map.put(acid_entry, :refs, refs)
  defp maybe_put_refs(acid_entry, _refs, false), do: acid_entry

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
   - `:total_requirements` - Total requirement count across all specs
   - `:canonical_specs_by_impl` - Map of impl_id => %{spec_id: id, is_inherited: bool, source_impl_id: id}

  ACIDs:
   - feature-view.ENG.1: Single query fetches all specs and implementations
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

        # Step 6: Batch resolve canonical specs for all implementations
        # feature-view.ENG.1: Precompute canonical spec resolution to avoid N+1
        canonical_specs_by_impl =
          batch_resolve_canonical_specs(actual_feature_name, implementations)

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
           canonical_specs_by_impl: canonical_specs_by_impl,
           total_requirements: total_requirements
         }}
    end
  end

  # --- Canonical Spec Resolution (Batched) ---

  @doc """
  Batch resolves canonical specs for multiple implementations and a single feature_name.

  Returns a map of implementation_id => %{spec_id: spec_id, is_inherited: boolean, source_impl_id: id | nil}
  where:
  - spec_id: the ID of the canonical spec for this implementation
  - is_inherited: true if the spec was found in a parent implementation
  - source_impl_id: the implementation ID where the spec was found (nil if local)

  Uses a batched query approach to avoid N+1 patterns:
  1. Fetches all implementations in the product to build ancestry chains
  2. Batch fetches tracked branches for all implementations and ancestors
  3. Batch fetches specs for those branches (scoped to product)
  4. For each implementation, walks the ancestry chain to find the first matching spec

  ACIDs:
  - feature-view.ENG.1: Batched query approach - constant queries regardless of implementation count
  - feature-impl-view.INHERITANCE.1: Recurse up parent chain via preloaded ancestry data
  - feature-impl-view.ROUTING.4: Same-product scoping for shared branches
  """
  def batch_resolve_canonical_specs(feature_name, implementations)
      when is_list(implementations) do
    if implementations == [] do
      %{}
    else
      product_id = List.first(implementations).product_id

      # Batch 1: Get all implementations in this product to build parent chains
      all_product_impls =
        Repo.all(
          from i in Acai.Implementations.Implementation,
            where: i.product_id == ^product_id,
            select: {i.id, i.parent_implementation_id}
        )
        |> Map.new()

      # Build ancestor chains for all implementations (self + all parents)
      ancestors_by_impl =
        Map.new(implementations, fn impl ->
          {impl.id, build_ancestor_chain_ordered(impl.id, all_product_impls)}
        end)

      # Get all ancestor IDs to fetch their tracked branches
      all_ancestor_ids =
        ancestors_by_impl
        |> Map.values()
        |> List.flatten()
        |> Enum.uniq()

      # Batch 2: Get all tracked branch IDs for all implementations and ancestors
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

      # Batch 3: Get all specs for these branches that match the feature_name
      # Grouped by branch_id => spec
      specs_by_branch =
        if all_branch_ids == [] do
          %{}
        else
          Repo.all(
            from s in Spec,
              where:
                s.branch_id in ^all_branch_ids and
                  s.feature_name == ^feature_name and
                  s.product_id == ^product_id,
              select: {s.branch_id, s}
          )
          |> Map.new()
        end

      # Now resolve canonical spec for each implementation
      for implementation <- implementations,
          into: %{} do
        result =
          resolve_canonical_spec_with_batch_data(
            implementation.id,
            branch_ids_by_impl,
            specs_by_branch,
            ancestors_by_impl
          )

        {implementation.id, result}
      end
    end
  end

  # Resolve canonical spec for a single implementation using pre-fetched batch data
  # Returns %{spec_id: spec_id | nil, is_inherited: boolean, source_impl_id: id | nil}
  defp resolve_canonical_spec_with_batch_data(
         impl_id,
         branch_ids_by_impl,
         specs_by_branch,
         ancestors_by_impl
       ) do
    # Get the ancestor chain for this implementation (self first, then parents)
    ancestor_chain = Map.get(ancestors_by_impl, impl_id, [impl_id])

    # Walk the chain to find the first spec
    Enum.reduce_while(
      ancestor_chain,
      %{spec_id: nil, is_inherited: false, source_impl_id: nil},
      fn current_impl_id, _acc ->
        branch_ids = Map.get(branch_ids_by_impl, current_impl_id, MapSet.new())

        # Find the first spec that matches any of these branches
        spec =
          branch_ids
          |> MapSet.to_list()
          |> Enum.find_value(fn branch_id ->
            Map.get(specs_by_branch, branch_id)
          end)

        if spec do
          is_inherited = current_impl_id != impl_id
          source_impl_id = if is_inherited, do: current_impl_id, else: nil
          {:halt, %{spec_id: spec.id, is_inherited: is_inherited, source_impl_id: source_impl_id}}
        else
          {:cont, %{spec_id: nil, is_inherited: false, source_impl_id: nil}}
        end
      end
    )
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
                join: b in assoc(s, :branch),
                where:
                  s.feature_name == ^feature_name and
                    s.branch_id in ^branch_ids and
                    s.product_id == ^product_id,
                order_by: [desc: s.updated_at, asc: b.branch_name, asc: s.id],
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
