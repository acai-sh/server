defmodule Acai.Services.Push do
  @moduledoc """
  Service module for handling push operations.

  This module orchestrates the full push flow including:
  - Branch resolution/creation
  - Product/implementation resolution
  - Spec writes
  - Ref writes
  - State writes

  All operations are wrapped in a transaction for atomicity.

  See push.TX.1, push.feature.yaml
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Teams.AccessToken
  alias Acai.Implementations.{Branch, Implementation, TrackedBranch}
  alias Acai.Products.Product
  alias Acai.Specs.{Spec, FeatureImplState, FeatureBranchRef}

  @normalized_param_keys %{
    "repo_uri" => :repo_uri,
    "branch_name" => :branch_name,
    "commit_hash" => :commit_hash,
    "specs" => :specs,
    "references" => :references,
    "states" => :states,
    "target_impl_name" => :target_impl_name,
    "parent_impl_name" => :parent_impl_name,
    "feature" => :feature,
    "requirements" => :requirements,
    "meta" => :meta,
    "name" => :name,
    "product" => :product,
    "description" => :description,
    "version" => :version,
    "prerequisites" => :prerequisites,
    "path" => :path,
    "raw_content" => :raw_content,
    "last_seen_commit" => :last_seen_commit,
    "data" => :data,
    "override" => :override
  }

  @write_scopes ["specs:write", "refs:write", "states:write", "impls:write"]

  @untracked_states_error "Cannot push states: branch is not tracked by any implementation. Push specs first or use target_impl_name to link to an existing implementation."

  @doc """
  Executes a push operation.

  Returns {:ok, response_map} on success or {:error, reason} on failure.

  ## Parameters
    - token: The authenticated AccessToken
    - params: The validated push request parameters
  """
  def execute(%AccessToken{} = token, params) do
    # push.REQUEST.4, push.REQUEST.5, push.REQUEST.6, push.REQUEST.7, push.REQUEST.8
    # Normalize params once at entry point to avoid repeated atom/string key lookups
    normalized_params = normalize_params(params)

    # Check required scopes based on what parts of the request are present
    with :ok <- check_scopes(token, normalized_params) do
      Repo.run_transaction(fn ->
        do_push(token, normalized_params)
      end)
    end
  end

  # push.REQUEST.4, push.REQUEST.5, push.REQUEST.6, push.REQUEST.7, push.REQUEST.8
  # Normalize incoming params to use atom keys consistently throughout the service.
  # This eliminates the need for defensive `params[:key] || params["key"]` lookups.
  defp normalize_params(params) when is_map(params) do
    params
    |> normalize_map_keys()
    |> normalize_nested_params()
  end

  defp normalize_params(params), do: params

  # Convert string keys to atom keys for top-level params only.
  # Nested maps (specs, references, states) are handled separately to preserve
  # user-defined string keys in data payloads (like ACIDs).
  defp normalize_map_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, normalize_param_key(key), value)
    end)
  end

  defp normalize_param_key(key) when is_binary(key), do: Map.get(@normalized_param_keys, key, key)
  defp normalize_param_key(key), do: key

  # Normalize nested structures in specs, references, and states
  defp normalize_nested_params(params) do
    params
    |> Map.update(:specs, [], &normalize_specs/1)
    |> Map.update(:references, nil, &normalize_map_keys/1)
    |> Map.update(:states, nil, &normalize_map_keys/1)
  end

  # Normalize each spec in the specs list
  defp normalize_specs(nil), do: []
  defp normalize_specs(specs) when is_list(specs), do: Enum.map(specs, &normalize_spec/1)
  defp normalize_specs(_), do: []

  defp normalize_spec(spec) when is_map(spec) do
    spec
    |> normalize_map_keys()
    |> Map.update(:feature, nil, &normalize_map_keys/1)
    |> Map.update(:meta, nil, &normalize_map_keys/1)

    # Keep requirements as-is since ACIDs are user-defined strings
  end

  defp normalize_spec(spec), do: spec

  # push.AUTH.2, push.AUTH.3, push.AUTH.4, push.AUTH.5
  # Convert token scopes to a set-like structure once and derive all checks from it
  defp check_scopes(token, params) do
    # Build a scope lookup map once to avoid 4 separate token_has_scope? calls
    scope_map = build_scope_map(token)

    specs = params[:specs] || []
    refs = params[:references]
    states = params[:states]
    has_specs = specs != []

    # If pushing specs, need specs:write
    cond do
      has_specs and not scope_map["specs:write"] ->
        {:error, "Token missing required scope: specs:write"}

      refs != nil and not scope_map["refs:write"] ->
        {:error, "Token missing required scope: refs:write"}

      states != nil and not scope_map["states:write"] ->
        {:error, "Token missing required scope: states:write"}

      has_specs and not scope_map["impls:write"] ->
        {:error, "Token missing required scope: impls:write"}

      true ->
        :ok
    end
  end

  # push.AUTH.2, push.AUTH.3, push.AUTH.4, push.AUTH.5
  # Build a map of scope -> boolean for O(1) lookups instead of multiple function calls
  defp build_scope_map(%AccessToken{} = token) do
    scopes = MapSet.new(token.scopes || [])

    Map.new(@write_scopes, fn scope -> {scope, MapSet.member?(scopes, scope)} end)
  end

  defp do_push(token, params) do
    try do
      do_push_internal(token, params)
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_push_internal(token, params) do
    # push.REQUEST.4, push.REQUEST.5, push.REQUEST.6, push.REQUEST.7, push.REQUEST.8
    # Params are already normalized to use atom keys at entry point
    team_id = token.team_id
    repo_uri = params[:repo_uri]
    branch_name = params[:branch_name]
    commit_hash = params[:commit_hash]
    specs = params[:specs] || []
    refs_data = params[:references]
    states_data = params[:states]
    target_impl_name = params[:target_impl_name]
    parent_impl_name = params[:parent_impl_name]

    # Step 1: Get or create the branch
    # push.REQUEST.1, push.REQUEST.2, push.REQUEST.3
    # data-model.BRANCHES.6, data-model.BRANCHES.6-1
    {:ok, branch} =
      Acai.Implementations.get_or_create_branch(%{
        team_id: team_id,
        repo_uri: repo_uri,
        branch_name: branch_name,
        last_seen_commit: commit_hash
      })

    # Step 2: If specs are present, handle product/implementation resolution
    # This also validates multi-product constraint
    # push.NEW_IMPLS.3, push.NEW_IMPLS.4
    {product, implementation, warnings} =
      if specs != [] do
        handle_specs_push(team_id, branch, specs, target_impl_name, parent_impl_name)
      else
        # No specs - just resolve existing implementation if any
        resolve_existing_implementation(team_id, branch, target_impl_name, states_data)
      end

    # Step 3: Write specs
    # push.INSERT_SPEC.1, push.UPDATE_SPEC.1, push.UPDATE_SPEC.2, push.UPDATE_SPEC.3
    {specs_created, specs_updated} =
      if specs != [] and implementation do
        write_specs(branch, product, specs)
      else
        {0, 0}
      end

    # Step 4: Write refs (can be done independently of specs)
    # push.REFS.3, push.REFS.4, push.WRITE_REFS.1, push.WRITE_REFS.2, push.WRITE_REFS.3
    maybe_write_refs(branch, refs_data, commit_hash)

    # Step 5: Write states (only if we have an implementation)
    # push.WRITE_STATES.1
    case maybe_write_states(implementation, states_data, parent_impl_name) do
      {:error, msg} ->
        {:error, msg}

      :ok ->
        {:ok,
         build_response(branch, product, implementation, specs_created, specs_updated, warnings)}
    end
  end

  # push.REFS.3, push.REFS.4, push.WRITE_REFS.1, push.WRITE_REFS.2, push.WRITE_REFS.3
  defp maybe_write_refs(_branch, nil, _commit_hash), do: :ok

  defp maybe_write_refs(branch, refs_data, commit_hash) do
    write_refs(branch, refs_data, commit_hash)
  end

  # push.NEW_IMPLS.2, push.WRITE_STATES.1
  defp maybe_write_states(_implementation, nil, _parent_impl_name), do: :ok

  defp maybe_write_states(implementation, states_data, parent_impl_name)
       when not is_nil(implementation) do
    write_states(implementation, states_data, parent_impl_name)
  end

  defp maybe_write_states(nil, _states_data, _parent_impl_name) do
    {:error, @untracked_states_error}
  end

  # push.RESPONSE.1, push.RESPONSE.2, push.RESPONSE.3, push.RESPONSE.4
  defp build_response(branch, product, implementation, specs_created, specs_updated, warnings) do
    %{
      implementation_name: implementation && implementation.name,
      implementation_id: implementation && to_string(implementation.id),
      product_name: product && product.name,
      branch_id: to_string(branch.id),
      specs_created: specs_created,
      specs_updated: specs_updated,
      warnings: Enum.map(warnings, &to_string/1)
    }
  end

  defp extract_feature_names_from_specs(specs) do
    Enum.map(specs, fn spec_input ->
      spec_input
      |> Map.get(:feature, %{})
      |> Map.get(:name)
    end)
  end

  defp implementation_trackings_for_branch(branch) do
    Repo.all(
      from tb in TrackedBranch,
        where: tb.branch_id == ^branch.id,
        preload: [implementation: :product]
    )
  end

  defp find_product(team_id, product_name) do
    Repo.one(
      from p in Product,
        where: p.team_id == ^team_id and p.name == ^product_name
    )
  end

  defp fetch_implementation_name_collision(team_id, product_id, implementation_name) do
    Repo.one(
      from i in Implementation,
        where:
          i.product_id == ^product_id and i.name == ^implementation_name and i.team_id == ^team_id
    )
  end

  defp maybe_track_branch(implementation, branch) do
    existing_trackings = Repo.all(from tb in TrackedBranch, where: tb.branch_id == ^branch.id)

    if existing_trackings == [] do
      {:ok, _} =
        TrackedBranch.changeset(%TrackedBranch{}, %{
          implementation_id: implementation.id,
          branch_id: branch.id,
          repo_uri: branch.repo_uri
        })
        |> Repo.insert()
    end

    :ok
  end

  defp maybe_validate_shared_product!(target_impl, parent_impl, parent_impl_name) do
    if parent_impl != nil and target_impl != nil and
         target_impl.product_id != parent_impl.product_id do
      throw(
        {:error,
         "Parent implementation '#{parent_impl_name}' must belong to the same product as the specs"}
      )
    end
  end

  defp maybe_raise_name_collision!(existing_impl, implementation_name) do
    if existing_impl do
      throw(
        {:error,
         "Implementation name '#{implementation_name}' already exists for this product. Please provide a target_impl_name to link to the existing implementation or choose a different name."}
      )
    end
  end

  # push.NEW_IMPLS.4, push.VALIDATION.3, push.VALIDATION.4
  # Shared helper: Extract unique product names from specs list.
  # Eliminates duplicate product name extraction logic.
  defp extract_product_names_from_specs(specs) when is_list(specs) do
    specs
    |> Enum.map(fn spec ->
      feature = spec[:feature] || %{}
      feature[:product]
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  defp extract_product_names_from_specs(_), do: []

  # Handle specs push - creates/links implementation and product
  # push.NEW_IMPLS.1, push.NEW_IMPLS.2, push.NEW_IMPLS.3, push.NEW_IMPLS.4, push.NEW_IMPLS.5
  # push.LINK_IMPLS.1, push.LINK_IMPLS.2, push.LINK_IMPLS.3
  # push.EXISTING_IMPLS.1, push.EXISTING_IMPLS.2, push.EXISTING_IMPLS.3, push.EXISTING_IMPLS.4
  defp handle_specs_push(team_id, branch, specs, target_impl_name, parent_impl_name) do
    # push.NEW_IMPLS.4 - Get unique product names from specs using shared helper
    product_names = extract_product_names_from_specs(specs)

    # push.NEW_IMPLS.4 - Reject multi-product pushes
    if length(product_names) > 1 do
      throw(
        {:error,
         "Push rejected: specs span multiple products (#{Enum.join(product_names, ", ")}). All specs must belong to the same product."}
      )
    end

    product_name = List.first(product_names)

    # Check if branch is already tracked by any implementation
    existing_trackings = implementation_trackings_for_branch(branch)

    cond do
      # Case 1: Branch is already tracked by one or more implementations
      existing_trackings != [] ->
        handle_tracked_branch_push(team_id, existing_trackings, target_impl_name, specs)

      # Case 2: Branch is not tracked - look for target implementation or create new
      true ->
        handle_untracked_branch_push(
          team_id,
          branch,
          product_name,
          specs,
          target_impl_name,
          parent_impl_name
        )
    end
  end

  # Handle push when branch is already tracked
  # push.EXISTING_IMPLS.1, push.EXISTING_IMPLS.2, push.EXISTING_IMPLS.3, push.EXISTING_IMPLS.4
  defp handle_tracked_branch_push(_team_id, existing_trackings, target_impl_name, specs) do
    implementations = Enum.map(existing_trackings, & &1.implementation)

    implementation =
      cond do
        # Multiple implementations and no target specified
        # push.EXISTING_IMPLS.2
        length(implementations) > 1 and is_nil(target_impl_name) ->
          impl_names = Enum.map(implementations, & &1.name) |> Enum.join(", ")

          throw(
            {:error,
             "Branch is tracked by multiple implementations (#{impl_names}). Please provide target_impl_name to specify which implementation to push to."}
          )

        # Multiple implementations with target specified
        # push.EXISTING_IMPLS.3
        length(implementations) > 1 and not is_nil(target_impl_name) ->
          case Enum.find(implementations, &(&1.name == target_impl_name)) do
            nil ->
              throw({:error, "Target implementation '#{target_impl_name}' not found"})

            impl ->
              impl
          end

        # Single implementation
        true ->
          hd(implementations)
      end

    # If target_impl_name was provided, verify it matches
    # push.EXISTING_IMPLS.4
    if target_impl_name && implementation.name != target_impl_name do
      throw(
        {:error,
         "Branch is already tracked by implementation '#{implementation.name}' but target_impl_name '#{target_impl_name}' was specified"}
      )
    end

    # push.VALIDATION.3 - Verify all specs belong to the same product as the implementation
    # Reuse shared helper for product name extraction
    spec_product_names = extract_product_names_from_specs(specs)

    if spec_product_names != [] and
         hd(spec_product_names) != implementation.product.name do
      throw(
        {:error,
         "All specs must belong to the same product as the target implementation '#{implementation.name}' (product: '#{implementation.product.name}')"}
      )
    end

    {implementation.product, implementation, []}
  end

  # Handle push when branch is not tracked
  # push.NEW_IMPLS.1, push.NEW_IMPLS.3, push.NEW_IMPLS.5
  # push.LINK_IMPLS.1, push.LINK_IMPLS.2, push.LINK_IMPLS.3
  defp handle_untracked_branch_push(
         team_id,
         branch,
         product_name,
         _specs,
         target_impl_name,
         parent_impl_name
       ) do
    # push.NEW_IMPLS.3 - Get or create product
    product =
      case find_product(team_id, product_name) do
        nil ->
          # Create new product
          {:ok, product} =
            Product.changeset(%Product{}, %{name: product_name, team_id: team_id})
            |> Repo.insert()

          product

        existing ->
          existing
      end

    # push.LINK_IMPLS.1, push.PARENTS.1, push.NEW_IMPLS.5
    # Consolidate implementation lookups: batch fetch target and parent together when both present
    {target_impl, parent_impl} =
      fetch_implementations_consolidated(
        team_id,
        product,
        branch,
        target_impl_name,
        parent_impl_name
      )

    # push.VALIDATION.4 - Validate parent and target are in same product
    maybe_validate_shared_product!(target_impl, parent_impl, parent_impl_name)

    # Determine implementation name (for new implementations)
    impl_name = target_impl_name || branch.branch_name

    # push.NEW_IMPLS.5 - Check for name collision if creating new
    # We already fetched target_impl if target_impl_name was provided, so we only
    # need to check collision when NOT linking to existing implementation
    existing_impl_for_collision =
      if is_nil(target_impl_name) do
        fetch_implementation_name_collision(team_id, product.id, impl_name)
      else
        nil
      end

    implementation =
      cond do
        # push.LINK_IMPLS.1 - Linking to existing implementation
        target_impl_name && target_impl ->
          target_impl

        # push.NEW_IMPLS.5 - Creating new implementation - check for name collision
        existing_impl_for_collision ->
          maybe_raise_name_collision!(existing_impl_for_collision, impl_name)

        # push.NEW_IMPLS.1 - Create new implementation
        true ->
          create_implementation(team_id, product, impl_name, parent_impl)
      end

    maybe_track_branch(implementation, branch)

    {product, implementation, []}
  end

  # push.LINK_IMPLS.1, push.LINK_IMPLS.3, push.PARENTS.3, push.NEW_IMPLS.5
  # Consolidated helper: batch fetch target and parent implementations together when possible.
  # Returns {target_impl, parent_impl} tuple.
  # This reduces sequential queries by fetching related implementations in one query when both
  # target_impl_name and parent_impl_name are provided.
  defp fetch_implementations_consolidated(
         team_id,
         product,
         branch,
         target_impl_name,
         parent_impl_name
       ) do
    # Build list of names to fetch
    names_to_fetch =
      [target_impl_name, parent_impl_name]
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # Batch fetch all implementations by name in a single query when possible
    implementations_by_name =
      if names_to_fetch != [] do
        Repo.all(
          from i in Implementation,
            where:
              i.product_id == ^product.id and i.name in ^names_to_fetch and
                i.team_id == ^team_id
        )
        |> Map.new(fn impl -> {impl.name, impl} end)
      else
        %{}
      end

    # Resolve target implementation
    target_impl =
      if target_impl_name do
        case Map.get(implementations_by_name, target_impl_name) do
          nil ->
            throw({:error, "Target implementation '#{target_impl_name}' not found"})

          impl ->
            # push.LINK_IMPLS.3 - Check if implementation already tracks a branch in this repo
            existing_repo_tracking =
              Repo.one(
                from tb in TrackedBranch,
                  join: b in Branch,
                  on: tb.branch_id == b.id,
                  where: tb.implementation_id == ^impl.id and b.repo_uri == ^branch.repo_uri
              )

            if existing_repo_tracking do
              throw(
                {:error,
                 "Implementation '#{target_impl_name}' already tracks a branch in this repository. Cannot link to multiple branches in the same repo."}
              )
            end

            impl
        end
      else
        nil
      end

    # Resolve parent implementation
    parent_impl =
      if parent_impl_name do
        case Map.get(implementations_by_name, parent_impl_name) do
          nil ->
            throw({:error, "Parent implementation '#{parent_impl_name}' not found"})

          parent ->
            parent
        end
      else
        nil
      end

    {target_impl, parent_impl}
  end

  # Create new implementation
  # push.NEW_IMPLS.1, push.NEW_IMPLS.1-1
  # push.PARENTS.1, push.PARENTS.2
  defp create_implementation(team_id, product, name, parent_implementation) do
    attrs = %{
      name: name,
      product_id: product.id,
      team_id: team_id,
      is_active: true
    }

    attrs =
      if parent_implementation do
        Map.put(attrs, :parent_implementation_id, parent_implementation.id)
      else
        attrs
      end

    {:ok, implementation} =
      Implementation.changeset(%Implementation{}, attrs)
      |> Repo.insert()

    implementation
  end

  # Resolve existing implementation when no specs are pushed
  # push.NEW_IMPLS.2
  defp resolve_existing_implementation(_team_id, branch, target_impl_name, states_data) do
    existing_trackings = implementation_trackings_for_branch(branch)

    cond do
      # If states are being pushed but no implementation exists, reject
      states_data && existing_trackings == [] ->
        throw({:error, @untracked_states_error})

      existing_trackings == [] ->
        {nil, nil, []}

      true ->
        implementations = Enum.map(existing_trackings, & &1.implementation)

        implementation =
          cond do
            length(implementations) > 1 and is_nil(target_impl_name) ->
              impl_names = Enum.map(implementations, & &1.name) |> Enum.join(", ")

              throw(
                {:error,
                 "Branch is tracked by multiple implementations (#{impl_names}). Please provide target_impl_name to specify which implementation to push to."}
              )

            length(implementations) > 1 and not is_nil(target_impl_name) ->
              case Enum.find(implementations, &(&1.name == target_impl_name)) do
                nil ->
                  throw({:error, "Target implementation '#{target_impl_name}' not found"})

                impl ->
                  impl
              end

            true ->
              hd(implementations)
          end

        {implementation.product, implementation, []}
    end
  end

  # Write specs to the database using batch operations
  # push.INSERT_SPEC.1, push.UPDATE_SPEC.1, push.UPDATE_SPEC.2, push.UPDATE_SPEC.3
  # push.PERMANENCE.1, push.IDEMPOTENCY.1, push.TX.1
  defp write_specs(branch, product, specs) do
    now = DateTime.utc_now(:second)

    # Extract all feature_names from specs input (batch step 1)
    # Specs are already normalized to use atom keys
    feature_names = extract_feature_names_from_specs(specs)

    # Batch fetch all existing specs for this branch (batch step 2)
    existing_specs_map =
      Repo.all(
        from s in Spec,
          where: s.branch_id == ^branch.id and s.feature_name in ^feature_names
      )
      |> Map.new(fn spec -> {spec.feature_name, spec} end)

    # Build spec attrs and partition into inserts/updates (batch step 3)
    # All keys are already normalized to atoms
    {to_insert_attrs, to_upsert_attrs} =
      Enum.reduce(specs, {[], []}, fn spec_input, {inserts, upserts} ->
        feature = spec_input[:feature] || %{}
        requirements = spec_input[:requirements] || %{}
        meta = spec_input[:meta] || %{}

        feature_name = feature[:name]
        feature_description = feature[:description]
        feature_version = feature[:version] || "1.0.0"

        path = meta[:path]
        raw_content = meta[:raw_content]
        last_seen_commit = meta[:last_seen_commit]

        spec_attrs = %{
          branch_id: branch.id,
          product_id: product.id,
          feature_name: feature_name,
          feature_description: feature_description,
          feature_version: feature_version,
          path: path,
          raw_content: raw_content,
          last_seen_commit: last_seen_commit,
          parsed_at: now,
          # push.UPDATE_SPEC.3 - Requirements are completely overwritten
          requirements: normalize_requirements(requirements),
          inserted_at: now,
          updated_at: now
        }

        case Map.get(existing_specs_map, feature_name) do
          nil ->
            # Generate UUIDv7 for new specs (insert_all bypasses autogenerate)
            insert_attrs = Map.put(spec_attrs, :id, Acai.UUIDv7.autogenerate())
            {[insert_attrs | inserts], upserts}

          existing_spec ->
            # push.IDEMPOTENCY.1 - Check if spec actually changed before upserting
            if spec_changed?(existing_spec, spec_attrs) do
              # Include the existing id so we can count actual updates vs no-ops
              upsert_attrs = Map.put(spec_attrs, :id, existing_spec.id)
              {inserts, [upsert_attrs | upserts]}
            else
              # push.IDEMPOTENCY.1 - Identical spec, skip entirely (no insert or update)
              {inserts, upserts}
            end
        end
      end)

    # Validate all attrs before writing (preserve schema validations)
    validate_spec_attrs!(to_insert_attrs)
    validate_spec_attrs!(to_upsert_attrs)

    # Batch insert new specs (batch step 4)
    specs_created =
      if to_insert_attrs != [] do
        {count, _} =
          Repo.insert_all(Spec, to_insert_attrs,
            on_conflict: :nothing,
            conflict_target: [:branch_id, :feature_name]
          )

        count
      else
        0
      end

    # Batch upsert changed specs (batch step 5)
    # push.IDEMPOTENCY.1 - Only count specs that actually changed
    specs_updated =
      if to_upsert_attrs != [] do
        {count, _} =
          Repo.insert_all(Spec, to_upsert_attrs,
            on_conflict:
              {:replace,
               [
                 :feature_description,
                 :feature_version,
                 :path,
                 :raw_content,
                 :last_seen_commit,
                 :parsed_at,
                 :requirements,
                 :updated_at
               ]},
            conflict_target: [:id]
          )

        count
      else
        0
      end

    {specs_created, specs_updated}
  end

  # push.IDEMPOTENCY.1 - Check if incoming spec differs from existing spec
  # Compares all mutable fields to determine if an update is needed
  defp spec_changed?(existing_spec, new_attrs) do
    existing_spec.feature_description != new_attrs[:feature_description] or
      existing_spec.feature_version != new_attrs[:feature_version] or
      existing_spec.path != new_attrs[:path] or
      existing_spec.raw_content != new_attrs[:raw_content] or
      existing_spec.last_seen_commit != new_attrs[:last_seen_commit] or
      requirements_changed?(existing_spec.requirements, new_attrs[:requirements])
  end

  # push.IDEMPOTENCY.1 - Compare requirements handling JSONB string keys vs atom keys
  defp requirements_changed?(existing_reqs, new_reqs) do
    # Normalize both to string keys for comparison since JSONB stores string keys
    normalize_keys(existing_reqs) != normalize_keys(new_reqs)
  end

  # Recursively convert map keys to strings for consistent comparison
  defp normalize_keys(nil), do: %{}

  defp normalize_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), normalize_keys(v)} end)
    |> Map.new()
  end

  defp normalize_keys(list) when is_list(list), do: Enum.map(list, &normalize_keys/1)
  defp normalize_keys(value), do: value

  # Validate spec attrs using changesets to preserve schema validations
  # push.UPDATE_SPEC.2 - Validates feature_name, version, description, path, raw_content, requirements
  defp validate_spec_attrs!(attrs_list) do
    Enum.each(attrs_list, fn attrs ->
      changeset = Spec.changeset(%Spec{}, Map.drop(attrs, [:inserted_at, :updated_at, :id]))

      unless changeset.valid? do
        errors =
          Ecto.Changeset.traverse_errors(changeset, fn {msg, opts} ->
            Enum.reduce(opts, msg, fn {key, value}, acc ->
              String.replace(acc, "%{#{key}}", to_string(value))
            end)
          end)

        throw({:error, "Spec validation failed: #{inspect(errors)}"})
      end
    end)
  end

  # Normalize requirements from various input formats
  defp normalize_requirements(requirements) when is_map(requirements) do
    requirements
    |> Enum.map(fn {acid, defn} ->
      defn_map =
        case defn do
          %{} = map ->
            requirement_text = Map.get(map, :requirement) || Map.get(map, "requirement")
            definition_text = Map.get(map, :definition) || Map.get(map, "definition")

            map
            |> Map.drop([:definition, "definition"])
            |> Map.put_new(:requirement, requirement_text || definition_text || "")

          req when is_binary(req) ->
            %{requirement: req}

          _ ->
            %{requirement: ""}
        end

      {acid, defn_map}
    end)
    |> Map.new()
  end

  defp normalize_requirements(_), do: %{}

  # Write refs to the database using batch operations
  # push.REFS.1, push.REFS.3, push.REFS.4, push.REFS.5, push.REFS.6
  # push.WRITE_REFS.1, push.WRITE_REFS.2, push.WRITE_REFS.3, push.WRITE_REFS.4
  defp write_refs(branch, refs_data, commit_hash) do
    now = DateTime.utc_now(:second)
    # refs_data is already normalized to use atom keys
    data = refs_data[:data] || %{}
    # push.REFS.1 - Ensure override is a boolean (handles nil case)
    override = normalize_boolean(refs_data[:override])

    # Step 1: Group refs by feature_name with extracted feature_name (batch step 1)
    refs_by_feature = group_acid_data_by_feature(data)

    # Step 2: Batch fetch all existing FeatureBranchRef rows (batch step 2)
    feature_names = Map.keys(refs_by_feature)

    existing_refs_map =
      if feature_names != [] do
        Repo.all(
          from fbr in FeatureBranchRef,
            where: fbr.branch_id == ^branch.id and fbr.feature_name in ^feature_names
        )
        |> Map.new(fn fbr -> {fbr.feature_name, fbr} end)
      else
        %{}
      end

    # Step 3: Build final refs payloads for each touched feature (batch step 3)
    {to_insert_attrs, to_upsert_attrs} =
      Enum.reduce(refs_by_feature, {[], []}, fn {feature_name, acid_refs}, {inserts, upserts} ->
        refs_map =
          if override do
            # push.REFS.6 - Override replaces everything
            Map.new(acid_refs)
          else
            # push.REFS.5 - Merge: get existing and merge per-ACID
            existing =
              case Map.get(existing_refs_map, feature_name) do
                nil -> %{}
                fbr -> fbr.refs || %{}
              end

            incoming = Map.new(acid_refs)
            Map.merge(existing, incoming)
          end

        # push.WRITE_REFS.4 - Store commit hash
        attrs = %{
          branch_id: branch.id,
          feature_name: feature_name,
          refs: refs_map,
          commit: commit_hash,
          pushed_at: now,
          inserted_at: now,
          updated_at: now
        }

        case Map.get(existing_refs_map, feature_name) do
          nil ->
            # New insert - generate UUIDv7 since insert_all bypasses autogenerate
            insert_attrs = Map.put(attrs, :id, Acai.UUIDv7.autogenerate())
            {[insert_attrs | inserts], upserts}

          existing ->
            # push.REFS.5 - Existing row, will be upserted - include the id for the update
            upsert_attrs = Map.put(attrs, :id, existing.id)
            {inserts, [upsert_attrs | upserts]}
        end
      end)

    # Step 4: Batch insert new refs (batch step 4)
    if to_insert_attrs != [] do
      Repo.insert_all(FeatureBranchRef, to_insert_attrs,
        on_conflict: :nothing,
        conflict_target: [:branch_id, :feature_name]
      )
    end

    # Step 5: Batch upsert existing refs (batch step 5)
    if to_upsert_attrs != [] do
      Repo.insert_all(FeatureBranchRef, to_upsert_attrs,
        on_conflict:
          {:replace,
           [
             :refs,
             :commit,
             :pushed_at,
             :updated_at
           ]},
        conflict_target: [:id]
      )
    end

    :ok
  end

  # Helper to group ACID data by feature_name, extracting feature_name only once per entry
  # push.WRITE_REFS.1 - Groups refs by feature_name derived from ACID prefix
  defp group_acid_data_by_feature(data) when is_map(data) do
    data
    |> Enum.reduce(%{}, fn {acid, value}, acc ->
      feature_name = extract_feature_name_from_acid(acid)

      Map.update(acc, feature_name, [{acid, value}], fn existing ->
        [{acid, value} | existing]
      end)
    end)
  end

  defp group_acid_data_by_feature(_), do: %{}

  # Write states to the database using batch operations
  # push.STATES.1, push.STATES.3
  # push.WRITE_STATES.1, push.WRITE_STATES.2, push.WRITE_STATES.3, push.WRITE_STATES.4
  defp write_states(implementation, states_data, _parent_impl_name) do
    now = DateTime.utc_now(:second)
    # states_data is already normalized to use atom keys
    data = states_data[:data] || %{}
    # push.STATES.1 - Ensure override is a boolean (handles nil case)
    override = normalize_boolean(states_data[:override])

    # Step 1: Group states by feature_name with extracted feature_name (batch step 1)
    states_by_feature = group_acid_data_by_feature(data)
    feature_names = Map.keys(states_by_feature)

    # Step 2: Batch fetch all existing child FeatureImplState rows (batch step 2)
    existing_states_map =
      if feature_names != [] do
        Repo.all(
          from fis in FeatureImplState,
            where:
              fis.implementation_id == ^implementation.id and
                fis.feature_name in ^feature_names
        )
        |> Map.new(fn fis -> {fis.feature_name, fis} end)
      else
        %{}
      end

    # Step 3: If parent exists, batch fetch all parent states for touched features (batch step 3)
    parent_states_map =
      if not is_nil(implementation.parent_implementation_id) and feature_names != [] do
        Repo.all(
          from fis in FeatureImplState,
            where:
              fis.implementation_id == ^implementation.parent_implementation_id and
                fis.feature_name in ^feature_names
        )
        |> Map.new(fn fis -> {fis.feature_name, fis.states || %{}} end)
      else
        %{}
      end

    # Step 4: Build final states payloads for each touched feature (batch step 4)
    {to_insert_attrs, to_upsert_attrs} =
      Enum.reduce(states_by_feature, {[], []}, fn {feature_name, acid_states},
                                                  {inserts, upserts} ->
        existing_state = Map.get(existing_states_map, feature_name)

        states_map =
          cond do
            # push.WRITE_STATES.2 - First write: snapshot from parent then merge
            is_nil(existing_state) and not is_nil(implementation.parent_implementation_id) ->
              parent_states = Map.get(parent_states_map, feature_name, %{})
              incoming = Map.new(acid_states)
              Map.merge(parent_states, incoming)

            # push.WRITE_STATES.3 - Subsequent writes: patch existing (merge mode)
            existing_state != nil and not override ->
              incoming = Map.new(acid_states)
              Map.merge(existing_state.states || %{}, incoming)

            # push.STATES.1 - Override mode: replace entirely
            override ->
              Map.new(acid_states)

            # First write, no parent
            true ->
              Map.new(acid_states)
          end

        attrs = %{
          implementation_id: implementation.id,
          feature_name: feature_name,
          states: states_map,
          inserted_at: now,
          updated_at: now
        }

        case existing_state do
          nil ->
            # New insert - generate UUIDv7 since insert_all bypasses autogenerate
            insert_attrs = Map.put(attrs, :id, Acai.UUIDv7.autogenerate())
            {[insert_attrs | inserts], upserts}

          existing ->
            # push.WRITE_STATES.3 - Existing row, will be upserted - include the id for the update
            upsert_attrs = Map.put(attrs, :id, existing.id)
            {inserts, [upsert_attrs | upserts]}
        end
      end)

    # Step 5: Batch insert new states (batch step 5)
    if to_insert_attrs != [] do
      Repo.insert_all(FeatureImplState, to_insert_attrs,
        on_conflict: :nothing,
        conflict_target: [:implementation_id, :feature_name]
      )
    end

    # Step 6: Batch upsert existing states (batch step 6)
    if to_upsert_attrs != [] do
      Repo.insert_all(FeatureImplState, to_upsert_attrs,
        on_conflict: {:replace, [:states, :updated_at]},
        conflict_target: [:id]
      )
    end

    :ok
  end

  # Normalize a value to a boolean, handling nil
  # Returns false for nil or falsy values, true for truthy values
  defp normalize_boolean(nil), do: false
  defp normalize_boolean(false), do: false
  defp normalize_boolean("false"), do: false
  defp normalize_boolean(0), do: false
  defp normalize_boolean(_), do: true

  # Extract feature name from ACID (e.g., "my-feature.COMP.1" -> "my-feature")
  defp extract_feature_name_from_acid(acid) when is_binary(acid) do
    case String.split(acid, ".", parts: 2) do
      [feature_name, _] -> feature_name
      _ -> acid
    end
  end

  defp extract_feature_name_from_acid(_), do: "unknown"
end
