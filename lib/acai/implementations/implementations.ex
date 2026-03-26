defmodule Acai.Implementations do
  @moduledoc """
  Context for implementations, branches, and tracked branches.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Implementations.{Implementation, Branch, TrackedBranch}
  alias Acai.Products.Product
  alias Acai.Teams.Team
  alias Acai.Specs.FeatureImplState
  alias Acai.Specs

  # --- Implementations ---

  @doc """
  Lists all implementations for a product.
  """
  def list_implementations(%Product{} = product) do
    Repo.all(from i in Implementation, where: i.product_id == ^product.id)
  end

  @doc """
  Gets an implementation by team, product, and name.

  ACIDs:
  - implementations.FILTERS.1: Lists implementations only within the requested product and token team
  - feature-context.RESPONSE.13: Implementation lookup is part of canonical feature resolution
  """
  def get_implementation_by_team_and_product_name(%Team{} = team, %Product{} = product, name) do
    normalized_name = String.downcase(String.trim(name || ""))

    case Repo.one(
           from i in Implementation,
             where:
               i.team_id == ^team.id and
                 i.product_id == ^product.id and
                 fragment("lower(?)", i.name) == ^normalized_name,
             limit: 1
         ) do
      nil -> {:error, :not_found}
      implementation -> {:ok, implementation}
    end
  end

  @doc """
  Lists implementations for API reads within a team and product.

  Supports optional exact branch filtering and feature availability filtering.

  ACIDs:
  - implementations.FILTERS.1: Lists implementations only within the requested product and token team
  - implementations.FILTERS.2: Exact branch filter returns only implementations tracking that branch
  - implementations.FILTERS.3: branch_name without repo_uri is rejected by the caller
  - implementations.FILTERS.4: repo_uri without branch_name is rejected by the caller
  - implementations.FILTERS.5: feature_name filter excludes implementations that cannot resolve the feature
  - implementations.FILTERS.6: Feature availability uses canonical spec resolution rules
  - implementations.RESPONSE.6: Results are sorted by implementation_name
  """
  def list_api_implementations(%Team{} = team, %Product{} = product, opts \\ []) do
    branch_filter = Keyword.get(opts, :branch_filter)
    feature_name = Keyword.get(opts, :feature_name)

    implementations =
      case branch_filter do
        {repo_uri, branch_name} ->
          Repo.all(
            from i in Implementation,
              join: tb in TrackedBranch,
              on: tb.implementation_id == i.id,
              join: b in Branch,
              on: b.id == tb.branch_id,
              where: i.team_id == ^team.id and i.product_id == ^product.id,
              where: b.repo_uri == ^repo_uri and b.branch_name == ^branch_name,
              order_by: [asc: i.name]
          )
          |> Enum.uniq_by(& &1.id)

        nil ->
          Repo.all(
            from i in Implementation,
              where: i.team_id == ^team.id and i.product_id == ^product.id,
              order_by: [asc: i.name]
          )
      end

    if is_binary(feature_name) and feature_name != "" do
      # implementations.FILTERS.5, implementations.FILTERS.6
      availability = Specs.batch_check_feature_availability([feature_name], implementations)

      Enum.filter(implementations, fn implementation ->
        availability[{feature_name, implementation.id}] == true
      end)
    else
      implementations
    end
  end

  @doc """
  Lists active implementations for a product, ordered by inheritance tree.

  Returns implementations in tree order:
  - Parentless implementations (roots) appear first
  - Descendants appear depth-first under their parents
  - Siblings are ordered by name for determinism

  ACIDs:
  - product-view.MATRIX.1: Columns are active implementations sorted by inheritance order
  - product-view.MATRIX.1-1: Parentless implementations first, then descendants in tree order
  - product-view.MATRIX.1-2: Sorting respects language direction (LTR/RTL)
  """
  def list_active_implementations(%Product{} = product, opts \\ []) do
    direction = Keyword.get(opts, :direction, :ltr)

    implementations =
      Repo.all(
        from i in Implementation,
          where: i.product_id == ^product.id and i.is_active == true
      )

    order_implementations_by_tree(implementations, direction)
  end

  @doc """
  Orders implementations by inheritance tree structure.

  ## Options

    * `:direction` - `:ltr` (default) or `:rtl` for sibling ordering

  ## Examples

      iex> order_implementations_by_tree(implementations, :ltr)
      [%{name: "Root"}, %{name: "Child1"}, %{name: "GrandChild"}, %{name: "Child2"}]

      iex> order_implementations_by_tree(implementations, :rtl)
      [%{name: "Root"}, %{name: "Child2"}, %{name: "GrandChild"}, %{name: "Child1"}]
  """
  def order_implementations_by_tree(implementations, direction \\ :ltr) do
    # Build parent_id -> children map from the provided implementations
    children_by_parent =
      implementations
      |> Enum.group_by(& &1.parent_implementation_id)

    # Build a set of all implementation IDs in the input set
    implementation_ids = MapSet.new(implementations, & &1.id)

    # Identify root nodes: either no parent OR parent not in the active set
    # This ensures active implementations with inactive parents are still included
    roots =
      implementations
      |> Enum.filter(fn impl ->
        impl.parent_implementation_id == nil ||
          not MapSet.member?(implementation_ids, impl.parent_implementation_id)
      end)

    # Sort roots by name (respecting direction)
    sorted_roots = sort_siblings(roots, direction)

    # Depth-first traversal to build ordered list
    Enum.flat_map(sorted_roots, fn root ->
      build_tree_order(root, children_by_parent, direction)
    end)
  end

  # Sort siblings by name, respecting direction
  defp sort_siblings(implementations, :rtl) do
    # RTL: reverse alphabetical order
    Enum.sort_by(implementations, & &1.name, :desc)
  end

  defp sort_siblings(implementations, _) do
    # LTR (default): alphabetical order
    Enum.sort_by(implementations, & &1.name)
  end

  # Build tree order for a node and its descendants (depth-first)
  defp build_tree_order(implementation, children_by_parent, direction) do
    children = Map.get(children_by_parent, implementation.id, [])
    sorted_children = sort_siblings(children, direction)

    [
      implementation
      | Enum.flat_map(sorted_children, &build_tree_order(&1, children_by_parent, direction))
    ]
  end

  @doc """
  Gets an implementation by ID.
  """
  def get_implementation!(id), do: Repo.get!(Implementation, id)

  @doc """
  Gets an implementation by ID, returns nil if not found.
  """
  def get_implementation(id), do: Repo.get(Implementation, id)

  @doc """
  Creates an implementation for a product.
  """
  def create_implementation(_current_scope, %Product{} = product, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:product_id, product.id)
      |> Map.put(:team_id, product.team_id)

    %Implementation{}
    |> Implementation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an implementation.
  """
  def update_implementation(%Implementation{} = implementation, attrs) do
    implementation
    |> Implementation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for an implementation.
  """
  def change_implementation(%Implementation{} = implementation, attrs \\ %{}) do
    Implementation.changeset(implementation, attrs)
  end

  @doc """
  Builds a URL-safe slug for an implementation.

  Format: {sanitized_name}-{uuid_without_dashes}

  ACIDs:
  - feature-impl-view.ROUTING.1: Route uses impl_name-impl_id format
  - feature-impl-view.ROUTING.2: impl_name is sanitized and trimmed for URL safety
  - feature-impl-view.ROUTING.3: impl_id is the UUID used for lookup
  """
  def implementation_slug(%Implementation{} = implementation) do
    "#{sanitize_slug_part(implementation.name)}-#{uuid_without_dashes(implementation.id)}"
  end

  @doc """
  Gets an implementation by parsing the slug pattern: {impl_name}-{uuid_without_dashes}.
  Returns nil if not found or invalid format.

  ACIDs:
  - feature-impl-view.ROUTING.3: impl_id is the UUID used for lookup
  """
  def get_implementation_by_slug(slug) when is_binary(slug) do
    case Regex.run(~r/-([0-9a-fA-F]{32})$/, slug, capture: :all_but_first) do
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

  # --- Counting ---

  @doc """
  Counts active implementations for a product.
  """
  def count_active_implementations(%Product{} = product) do
    Repo.one(
      from i in Implementation,
        where: i.product_id == ^product.id and i.is_active == true,
        select: count()
    )
  end

  @doc """
  Batch counts active implementations for a list of products.
  Returns a map of product_id => count.
  """
  def batch_count_active_implementations_for_products(products) when is_list(products) do
    product_ids = Enum.map(products, & &1.id)

    Repo.all(
      from i in Implementation,
        where: i.product_id in ^product_ids and i.is_active == true,
        group_by: i.product_id,
        select: {i.product_id, count()}
    )
    |> Map.new()
  end

  # --- Branches ---

  @doc """
  Gets a branch by ID.
  """
  def get_branch!(id), do: Repo.get!(Branch, id)

  @doc """
  Gets a branch by its stable identity (team_id, repo_uri, branch_name).
  Returns nil if not found.

  ACID: data-model.BRANCHES.6-1
  """
  def get_branch_by_identity(team_id, repo_uri, branch_name) do
    Repo.one(
      from b in Branch,
        where: b.team_id == ^team_id and b.repo_uri == ^repo_uri and b.branch_name == ^branch_name
    )
  end

  @doc """
  Gets or creates a branch by its stable identity (team_id, repo_uri, branch_name).
  If the branch exists, updates last_seen_commit. Otherwise creates new.

  Requires :team_id in attrs.

  ACIDs:
  - data-model.BRANCHES.6
  - data-model.BRANCHES.6-1
  """
  def get_or_create_branch(attrs) do
    attrs = Map.new(attrs)
    team_id = attrs[:team_id] || attrs["team_id"]
    repo_uri = attrs[:repo_uri] || attrs["repo_uri"]
    branch_name = attrs[:branch_name] || attrs["branch_name"]
    last_seen_commit = attrs[:last_seen_commit] || attrs["last_seen_commit"]

    case get_branch_by_identity(team_id, repo_uri, branch_name) do
      nil ->
        %Branch{}
        |> Branch.changeset(attrs)
        |> Repo.insert()

      branch ->
        branch
        |> Branch.changeset(%{last_seen_commit: last_seen_commit})
        |> Repo.update()
    end
  end

  @doc """
  Updates a branch.
  """
  def update_branch(%Branch{} = branch, attrs) do
    branch
    |> Branch.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for a branch.
  """
  def change_branch(%Branch{} = branch, attrs \\ %{}) do
    Branch.changeset(branch, attrs)
  end

  @doc """
  Lists all branches for an implementation through tracked_branches.
  """
  def list_branches_for_implementation(%Implementation{} = implementation) do
    Repo.all(
      from b in Branch,
        join: tb in TrackedBranch,
        on: tb.branch_id == b.id,
        where: tb.implementation_id == ^implementation.id
    )
  end

  # --- Tracked Branches ---

  @doc """
  Lists all tracked branches for an implementation.
  Preloads the branch association.
  """
  def list_tracked_branches(%Implementation{} = implementation) do
    Repo.all(
      from tb in TrackedBranch,
        where: tb.implementation_id == ^implementation.id,
        preload: [:branch]
    )
  end

  @doc """
  Creates a tracked branch linking an implementation to a branch.

  The attrs must contain:
  - :branch_id - the ID of the branch to track
  - :repo_uri - the denormalized repo_uri for the unique constraint
  """
  def create_tracked_branch(%Implementation{} = implementation, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:implementation_id, implementation.id)

    %TrackedBranch{}
    |> TrackedBranch.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for a tracked branch.
  """
  def change_tracked_branch(%TrackedBranch{} = tracked_branch, attrs \\ %{}) do
    TrackedBranch.changeset(tracked_branch, attrs)
  end

  @doc """
  Deletes a tracked branch (untracks a branch from an implementation).

  ACIDs:
  - impl-settings.UNTRACK_BRANCH.7: On confirmation, removes the branch from tracked branches
  - impl-settings.DATA_INTEGRITY.1: Untrack operation preserves feature_branch_ref data
  """
  def delete_tracked_branch(%TrackedBranch{} = tracked_branch) do
    Repo.delete(tracked_branch)
  end

  @doc """
  Lists all trackable branches for an implementation.

  Trackable branches are defined as branches where repo_uri is not already tracked
  by this implementation. Excludes branches from other teams.

  ACIDs:
  - impl-settings.TRACK_BRANCH.2: Trackable branches where repo_uri is not already tracked
  - impl-settings.TRACK_BRANCH.3_1: Excludes branches already tracked by this implementation
  - impl-settings.TRACK_BRANCH.3_2: Excludes branches for other teams
  - impl-settings.TRACK_BRANCH.4: Each option displays full repo_uri plus branch name
  """
  def list_trackable_branches(%Implementation{} = implementation) do
    # Single efficient query that excludes already tracked repo_uris at the SQL level
    # Uses a subquery to get tracked repo_uris and filters them out in the main query
    tracked_repo_uris =
      from tb in TrackedBranch,
        where: tb.implementation_id == ^implementation.id,
        select: tb.repo_uri

    Repo.all(
      from b in Branch,
        where: b.team_id == ^implementation.team_id,
        where: b.repo_uri not in subquery(tracked_repo_uris),
        order_by: [b.repo_uri, b.branch_name]
    )
  end

  @doc """
  Deletes an implementation and handles cascading effects.

  ACIDs:
  - impl-settings.DELETE.6: On confirmation, permanently deletes the implementation
  - impl-settings.DATA_INTEGRITY.2: Delete operation cascades to clear dependent states (DB constraint)
  - impl-settings.DATA_INTEGRITY.3: Child implementations are not deleted, parent_implementation_id is cleared
  """
  def delete_implementation(%Implementation{} = implementation) do
    # impl-settings.DATA_INTEGRITY.3: Child implementations are not deleted
    # Use a transaction to ensure atomicity - if delete fails, children remain attached
    Repo.transaction(fn ->
      # Clear parent_implementation_id for child implementations
      # This preserves child implementations per data-model.IMPLS.7-1
      Repo.update_all(
        from(i in Implementation, where: i.parent_implementation_id == ^implementation.id),
        set: [parent_implementation_id: nil]
      )

      Repo.delete!(implementation)
    end)
  end

  @doc """
  Checks if a name is unique within a product for an implementation.

  Returns true if the name is available (not taken by another implementation
  in the same product), false otherwise.
  """
  def implementation_name_unique?(%Implementation{} = implementation, name) do
    trimmed_name = String.trim(name)

    existing =
      Repo.one(
        from i in Implementation,
          where:
            i.product_id == ^implementation.product_id and
              fragment("lower(?)", i.name) == ^String.downcase(trimmed_name) and
              i.id != ^implementation.id,
          limit: 1
      )

    is_nil(existing)
  end

  @doc """
  Counts tracked branches for an implementation.
  """
  def count_tracked_branches(%Implementation{} = implementation) do
    Repo.one(
      from tb in TrackedBranch,
        where: tb.implementation_id == ^implementation.id,
        select: count()
    )
  end

  @doc """
  Batch counts tracked branches for a list of implementations.
  Returns a map of implementation_id => count.
  """
  def batch_count_tracked_branches(implementations) when is_list(implementations) do
    impl_ids = Enum.map(implementations, & &1.id)

    Repo.all(
      from tb in TrackedBranch,
        where: tb.implementation_id in ^impl_ids,
        group_by: tb.implementation_id,
        select: {tb.implementation_id, count()}
    )
    |> Map.new()
  end

  # --- FeatureImplState Counts ---

  @doc """
  Gets feature_impl_state counts for an implementation.
  Returns %{nil => count, assigned: count, blocked: count, completed: count, accepted: count, rejected: count}
  """
  def get_feature_impl_state_counts(%Implementation{} = implementation) do
    state =
      Repo.one(
        from fis in FeatureImplState,
          where: fis.implementation_id == ^implementation.id,
          select: fis.states
      ) || %{}

    counts = %{
      nil => 0,
      "assigned" => 0,
      "blocked" => 0,
      "completed" => 0,
      "accepted" => 0,
      "rejected" => 0
    }

    Enum.reduce(state, counts, fn {_acid, attrs}, acc ->
      status = attrs["status"]
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  # Deprecated: Use get_feature_impl_state_counts/1 instead
  def get_spec_impl_state_counts(%Implementation{} = implementation) do
    get_feature_impl_state_counts(implementation)
  end

  @doc """
  Batch gets feature_impl_state counts for multiple implementations and optional feature_names.
  Returns a map of implementation_id => %{nil => count, assigned: count, blocked: count, completed: count, accepted: count, rejected: count}

  When feature_names are provided, only counts states for those features. Otherwise counts all states.
  """
  def batch_get_feature_impl_state_counts(implementations, specs \\ nil)
      when is_list(implementations) do
    impl_ids = Enum.map(implementations, & &1.id)
    feature_names = if specs, do: Enum.map(specs, & &1.feature_name) |> Enum.uniq(), else: nil

    states =
      if feature_names do
        Repo.all(
          from fis in FeatureImplState,
            where: fis.implementation_id in ^impl_ids and fis.feature_name in ^feature_names,
            select: {fis.implementation_id, fis.states}
        )
      else
        Repo.all(
          from fis in FeatureImplState,
            where: fis.implementation_id in ^impl_ids,
            select: {fis.implementation_id, fis.states}
        )
      end

    # Aggregate states from multiple feature_names per implementation
    # Each implementation may have multiple rows (one per feature_name), so we merge them
    states_by_impl =
      Enum.reduce(states, %{}, fn {impl_id, feature_states}, acc ->
        Map.update(acc, impl_id, feature_states, &Map.merge(&1, feature_states))
      end)

    impl_ids
    |> Map.new(fn impl_id ->
      state = Map.get(states_by_impl, impl_id, %{})

      counts = %{
        nil => 0,
        "assigned" => 0,
        "blocked" => 0,
        "completed" => 0,
        "accepted" => 0,
        "rejected" => 0
      }

      final_counts =
        Enum.reduce(state, counts, fn {_acid, attrs}, acc ->
          status = attrs["status"]
          Map.update(acc, status, 1, &(&1 + 1))
        end)

      {impl_id, final_counts}
    end)
  end

  # Deprecated: Use batch_get_feature_impl_state_counts/2 instead
  def batch_get_spec_impl_state_counts(implementations, specs \\ nil) do
    batch_get_feature_impl_state_counts(implementations, specs)
  end

  @doc """
  Batch gets feature_impl_state counts for multiple implementations with inheritance.
  Returns a map of implementation_id => %{nil => count, assigned: count, blocked: count, completed: count, accepted: count, rejected: count}

  For each implementation, if no local states exist for the given feature_names,
  walks the parent_implementation_id chain to find inherited states.

  ACIDs:
  - feature-view.ENG.2: Respects inheritance semantics for state counts
  - feature-impl-view.INHERITANCE.1: Recurse up parent chain if states not found locally
  """
  def batch_get_feature_impl_state_counts_with_inheritance(implementations, specs \\ nil)
      when is_list(implementations) do
    if implementations == [] do
      %{}
    else
      feature_names = if specs, do: Enum.map(specs, & &1.feature_name) |> Enum.uniq(), else: nil

      # Get product_id from first implementation (all should be from same product)
      product_id = List.first(implementations).product_id

      # Build ancestor chains for all implementations
      ancestor_chains = build_ancestor_chains(implementations, product_id)

      # Collect all ancestor IDs (including self) to fetch states in one query
      all_impl_ids =
        ancestor_chains
        |> Map.values()
        |> List.flatten()
        |> Enum.uniq()

      # Fetch all states for all implementations and feature_names in one query
      # Group by implementation_id for efficient lookup
      raw_states =
        if feature_names do
          Repo.all(
            from fis in FeatureImplState,
              where:
                fis.implementation_id in ^all_impl_ids and fis.feature_name in ^feature_names,
              select: {fis.implementation_id, fis.states}
          )
        else
          Repo.all(
            from fis in FeatureImplState,
              where: fis.implementation_id in ^all_impl_ids,
              select: {fis.implementation_id, fis.states}
          )
        end

      states_by_impl =
        raw_states
        |> Enum.group_by(fn {impl_id, _} -> impl_id end, fn {_, states} -> states end)
        |> Map.new(fn {impl_id, states_list} ->
          # Merge all states for this implementation across feature_names
          merged_states = Enum.reduce(states_list, %{}, &Map.merge(&2, &1))
          {impl_id, merged_states}
        end)

      # For each implementation, find states (local or inherited) and aggregate counts
      result =
        Enum.map(implementations, fn impl ->
          # Get the ancestor chain for this implementation (self first, then parents)
          chain = Map.get(ancestor_chains, impl.id, [impl.id])

          # Find states for this implementation (checking self first, then ancestors)
          states = find_inherited_states(chain, states_by_impl)

          # Aggregate counts from the states
          counts = aggregate_state_counts(states)

          {impl.id, counts}
        end)
        |> Map.new()

      result
    end
  end

  # Build ancestor chains for all implementations in one batch query
  # Returns a map of impl_id => [impl_id, parent_id, grandparent_id, ...]
  defp build_ancestor_chains(implementations, product_id) do
    _impl_ids = Enum.map(implementations, & &1.id)

    # Get all implementations in this product to build parent chains
    all_product_impls =
      Repo.all(
        from i in Implementation,
          where: i.product_id == ^product_id,
          select: {i.id, i.parent_implementation_id}
      )
      |> Map.new()

    # Build ancestor chain for each implementation
    Map.new(implementations, fn impl ->
      chain = build_ancestor_chain(impl.id, all_product_impls)
      {impl.id, chain}
    end)
  end

  # Build ancestor chain for a single implementation (self + all parents)
  # Returns list in order: [self_id, parent_id, grandparent_id, ...]
  defp build_ancestor_chain(impl_id, all_impls_map, visited \\ MapSet.new()) do
    do_build_ancestor_chain_ordered(impl_id, all_impls_map, visited, [])
  end

  # Helper that builds chain in correct order (self first, then ancestors)
  defp do_build_ancestor_chain_ordered(nil, _all_impls_map, _visited, acc), do: acc

  defp do_build_ancestor_chain_ordered(impl_id, all_impls_map, visited, acc) do
    if MapSet.member?(visited, impl_id) do
      # Circular reference detected
      acc
    else
      visited = MapSet.put(visited, impl_id)
      parent_id = Map.get(all_impls_map, impl_id)
      # Add current impl to front of chain, then continue with parent
      do_build_ancestor_chain_ordered(parent_id, all_impls_map, visited, acc ++ [impl_id])
    end
  end

  # Find states for an implementation, checking self first then ancestors
  # Returns a merged map of acid => attrs from the FIRST implementation in chain that has states
  defp find_inherited_states(chain, states_by_impl) do
    # For each implementation in the chain (starting from self), check if it has states
    Enum.reduce_while(chain, %{}, fn impl_id, _acc ->
      case Map.get(states_by_impl, impl_id) do
        nil ->
          # No states at this level, continue to next ancestor
          {:cont, %{}}

        states when map_size(states) > 0 ->
          # Found states at this level, use them and stop searching
          {:halt, states}

        _ ->
          # Empty states map, continue to next ancestor
          {:cont, %{}}
      end
    end)
  end

  # Aggregate state counts from a states map
  defp aggregate_state_counts(states) do
    counts = %{
      nil => 0,
      "assigned" => 0,
      "blocked" => 0,
      "completed" => 0,
      "accepted" => 0,
      "rejected" => 0
    }

    Enum.reduce(states, counts, fn {_acid, attrs}, acc ->
      status = attrs["status"]
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  # --- Active Implementations for Specs ---

  @doc """
  Lists all active implementations for a list of specs.
  This finds implementations through the product relationship.
  """
  def list_active_implementations_for_specs(specs) when is_list(specs) do
    product_ids = specs |> Enum.map(& &1.product_id) |> Enum.uniq()

    Repo.all(
      from i in Implementation,
        where: i.product_id in ^product_ids and i.is_active == true
    )
  end

  # --- Feature Branch Refs Aggregation ---

  alias Acai.Specs.FeatureBranchRef

  @doc """
  Gets tracked branch IDs for an implementation.

  ACID: data-model.INHERITANCE.8
  """
  def get_tracked_branch_ids(%Implementation{} = implementation) do
    Repo.all(
      from tb in TrackedBranch,
        where: tb.implementation_id == ^implementation.id,
        select: tb.branch_id
    )
  end

  @doc """
  Aggregates feature_branch_refs for a feature_name across given branch IDs.
  Returns a list of {branch, refs_map} tuples where refs_map is %{acid => [ref_objects]}.

  ACIDs:
  - data-model.FEATURE_BRANCH_REFS.4: refs stored as JSONB
  - data-model.FEATURE_BRANCH_REFS.4-1: refs keyed by ACID
  """
  def aggregate_feature_branch_refs(branch_ids, feature_name) when is_list(branch_ids) do
    if branch_ids == [] do
      []
    else
      Repo.all(
        from fbr in FeatureBranchRef,
          join: b in Branch,
          on: fbr.branch_id == b.id,
          where: fbr.branch_id in ^branch_ids and fbr.feature_name == ^feature_name,
          preload: [:branch]
      )
      |> Enum.map(fn fbr ->
        {fbr.branch, fbr.refs}
      end)
    end
  end

  @doc """
  Gets aggregated refs across all tracked branches for a feature_name and implementation.
  Walks the parent implementation chain if no refs found on tracked branches.

  Returns {aggregated_refs, source_impl_id} where:
  - aggregated_refs: list of {branch, refs_map} tuples
  - source_impl_id: nil if refs are from this implementation, or the ID of the parent
    implementation where the refs were inherited from

  ACIDs:
  - data-model.INHERITANCE.8: Aggregate refs across tracked branches, walk parent chain
  - data-model.INHERITANCE.9: feature_name-based keys for monorepo support
  - feature-impl-view.INHERITANCE.3: Refs aggregated from tracked branches
  """
  def get_aggregated_refs_with_inheritance(
        feature_name,
        implementation_id,
        visited \\ MapSet.new()
      ) do
    get_aggregated_refs_with_inheritance_impl(feature_name, implementation_id, nil, visited)
  end

  # Internal implementation that tracks the original implementation ID for inheritance
  defp get_aggregated_refs_with_inheritance_impl(
         feature_name,
         implementation_id,
         original_impl_id,
         visited
       ) do
    # Prevent infinite loops in case of circular references
    if MapSet.member?(visited, implementation_id) do
      {[], nil}
    else
      visited = MapSet.put(visited, implementation_id)
      implementation = Repo.get(Implementation, implementation_id)

      if is_nil(implementation) do
        {[], nil}
      else
        # Get tracked branch IDs for this implementation
        branch_ids = get_tracked_branch_ids(implementation)

        # Aggregate refs from tracked branches
        refs = aggregate_feature_branch_refs(branch_ids, feature_name)

        if refs != [] do
          # Found refs on this implementation's branches
          # If we walked up the parent chain, return the current impl ID as source
          source_impl_id = if original_impl_id, do: implementation_id, else: nil
          {refs, source_impl_id}
        else
          # No refs found, check parent implementation
          if implementation.parent_implementation_id do
            # Track the original implementation ID on first call
            orig_id = original_impl_id || implementation_id

            {parent_refs, source_impl_id} =
              get_aggregated_refs_with_inheritance_impl(
                feature_name,
                implementation.parent_implementation_id,
                orig_id,
                visited
              )

            if parent_refs != [] do
              {parent_refs, source_impl_id}
            else
              {[], nil}
            end
          else
            {[], nil}
          end
        end
      end
    end
  end

  @doc """
  Counts total refs and tests for a feature_name and implementation.
  Returns %{total_refs: count, total_tests: count, is_inherited: boolean}.
  """
  def count_refs_for_implementation(feature_name, implementation_id) do
    {aggregated_refs, source_impl_id} =
      get_aggregated_refs_with_inheritance(feature_name, implementation_id)

    {total_refs, total_tests} =
      Enum.reduce(aggregated_refs, {0, 0}, fn {_branch, refs_map}, {refs_acc, tests_acc} ->
        Enum.reduce(refs_map, {refs_acc, tests_acc}, fn {_acid, ref_list}, {r_acc, t_acc} ->
          ref_count = Enum.count(ref_list, fn ref -> not Map.get(ref, "is_test", false) end)
          test_count = Enum.count(ref_list, fn ref -> Map.get(ref, "is_test", false) end)
          {r_acc + ref_count, t_acc + test_count}
        end)
      end)

    %{total_refs: total_refs, total_tests: total_tests, is_inherited: source_impl_id != nil}
  end

  @doc """
  Gets all refs for a specific ACID across aggregated branch refs.
  Returns list of {branch, ref_objects} tuples.

  ACID: feature-impl-view.DRAWER.4: Lists all refs for this ACID
  """
  def get_refs_for_acid(aggregated_refs, acid) when is_list(aggregated_refs) do
    aggregated_refs
    |> Enum.flat_map(fn {branch, refs_map} ->
      case Map.get(refs_map, acid) do
        nil -> []
        ref_list when is_list(ref_list) -> [{branch, ref_list}]
        _ -> []
      end
    end)
  end
end
