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

  @doc """
  Executes a push operation.

  Returns {:ok, response_map} on success or {:error, reason} on failure.

  ## Parameters
    - token: The authenticated AccessToken
    - params: The validated push request parameters

  See push.feature.yaml for all ACIDs
  """
  def execute(%AccessToken{} = token, params) do
    # Check required scopes based on what parts of the request are present
    with :ok <- check_scopes(token, params) do
      Repo.run_transaction(fn ->
        do_push(token, params)
      end)
    end
  end

  # push.AUTH.2, push.AUTH.3, push.AUTH.4, push.AUTH.5
  defp check_scopes(token, params) do
    specs = params[:specs] || params["specs"] || []
    refs = params[:references] || params["references"]
    states = params[:states] || params["states"]
    has_specs = specs != []

    has_refs_write = Acai.Teams.token_has_scope?(token, "refs:write")
    has_states_write = Acai.Teams.token_has_scope?(token, "states:write")
    has_specs_write = Acai.Teams.token_has_scope?(token, "specs:write")
    has_impls_write = Acai.Teams.token_has_scope?(token, "impls:write")

    # If pushing specs, need specs:write
    cond do
      has_specs and not has_specs_write ->
        {:error, "Token missing required scope: specs:write"}

      refs != nil and not has_refs_write ->
        {:error, "Token missing required scope: refs:write"}

      states != nil and not has_states_write ->
        {:error, "Token missing required scope: states:write"}

      has_specs and not has_impls_write ->
        {:error, "Token missing required scope: impls:write"}

      true ->
        :ok
    end
  end

  defp do_push(token, params) do
    try do
      do_push_internal(token, params)
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_push_internal(token, params) do
    team_id = token.team_id
    repo_uri = params[:repo_uri] || params["repo_uri"]
    branch_name = params[:branch_name] || params["branch_name"]
    commit_hash = params[:commit_hash] || params["commit_hash"]
    specs = params[:specs] || params["specs"] || []
    refs_data = params[:references] || params["references"]
    states_data = params[:states] || params["states"]
    target_impl_name = params[:target_impl_name] || params["target_impl_name"]
    parent_impl_name = params[:parent_impl_name] || params["parent_impl_name"]

    _warnings = []

    # Step 1: Get or create the branch
    # push.REQUEST.1, push.REQUEST.2, push.REQUEST.3
    # data-model.BRANCHES.10, data-model.BRANCHES.10-1
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
    refs_warnings =
      if refs_data do
        write_refs(branch, refs_data, commit_hash)
        []
      else
        []
      end

    warnings = warnings ++ refs_warnings

    # Step 5: Write states (only if we have an implementation)
    # push.WRITE_STATES.1
    states_warnings =
      if states_data do
        if implementation do
          write_states(implementation, states_data, parent_impl_name)
          []
        else
          # push.NEW_IMPLS.2 - Reject states without implementation
          [
            {:error,
             "Cannot push states: branch is not tracked by any implementation. Push specs first or use target_impl_name to link to an existing implementation."}
          ]
        end
      else
        []
      end

    # Check for errors in warnings
    errors = Enum.filter(states_warnings, fn {type, _} -> type == :error end)

    if errors != [] do
      {_type, msg} = hd(errors)
      {:error, msg}
    else
      # Build response
      # push.RESPONSE.1, push.RESPONSE.2, push.RESPONSE.3, push.RESPONSE.4
      response = %{
        implementation_name: if(implementation, do: implementation.name),
        implementation_id: if(implementation, do: to_string(implementation.id)),
        product_name: if(product, do: product.name),
        branch_id: to_string(branch.id),
        specs_created: specs_created,
        specs_updated: specs_updated,
        warnings: Enum.map(warnings, &to_string/1)
      }

      {:ok, response}
    end
  end

  # Handle specs push - creates/links implementation and product
  # push.NEW_IMPLS.1, push.NEW_IMPLS.2, push.NEW_IMPLS.3, push.NEW_IMPLS.4, push.NEW_IMPLS.5
  # push.LINK_IMPLS.1, push.LINK_IMPLS.2, push.LINK_IMPLS.3
  # push.EXISTING_IMPLS.1, push.EXISTING_IMPLS.2, push.EXISTING_IMPLS.3, push.EXISTING_IMPLS.4
  defp handle_specs_push(team_id, branch, specs, target_impl_name, parent_impl_name) do
    # Get unique product names from specs
    product_names =
      specs
      |> Enum.map(fn spec ->
        feature = spec[:feature] || spec["feature"] || %{}
        feature[:product] || feature["product"]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

    # push.NEW_IMPLS.4 - Reject multi-product pushes
    if length(product_names) > 1 do
      throw(
        {:error,
         "Push rejected: specs span multiple products (#{Enum.join(product_names, ", ")}). All specs must belong to the same product."}
      )
    end

    product_name = List.first(product_names)

    # Check if branch is already tracked by any implementation
    existing_trackings =
      Repo.all(
        from tb in TrackedBranch,
          where: tb.branch_id == ^branch.id,
          preload: [implementation: :product]
      )

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

    # Verify all specs belong to the same product as the implementation
    # push.VALIDATION.3
    spec_product_names =
      specs
      |> Enum.map(fn spec ->
        feature = spec[:feature] || spec["feature"] || %{}
        feature[:product] || feature["product"]
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.uniq()

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
    # Get or create product
    # push.NEW_IMPLS.3
    product =
      case Repo.one(
             from p in Product,
               where: p.team_id == ^team_id and p.name == ^product_name
           ) do
        nil ->
          # Create new product
          {:ok, product} =
            Product.changeset(%Product{}, %{name: product_name, team_id: team_id})
            |> Repo.insert()

          product

        existing ->
          existing
      end

    # Check if target implementation exists
    implementation =
      if target_impl_name do
        # push.LINK_IMPLS.1
        case Repo.one(
               from i in Implementation,
                 where:
                   i.product_id == ^product.id and i.name == ^target_impl_name and
                     i.team_id == ^team_id
             ) do
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

    # Resolve parent implementation if specified
    parent_implementation =
      if parent_impl_name do
        # push.PARENTS.3
        case Repo.one(
               from i in Implementation,
                 where:
                   i.product_id == ^product.id and i.name == ^parent_impl_name and
                     i.team_id == ^team_id
             ) do
          nil ->
            throw({:error, "Parent implementation '#{parent_impl_name}' not found"})

          parent ->
            parent
        end
      else
        nil
      end

    # push.VALIDATION.4
    if parent_implementation != nil and target_impl_name != nil do
      target_impl = implementation || %Implementation{product_id: product.id}

      if target_impl.product_id != parent_implementation.product_id do
        throw(
          {:error,
           "Parent implementation '#{parent_impl_name}' must belong to the same product as the specs"}
        )
      end
    end

    # Determine implementation name (for new implementations)
    impl_name = target_impl_name || branch.branch_name

    # Check for name collision if creating new
    # push.NEW_IMPLS.5
    existing_impl =
      Repo.one(
        from i in Implementation,
          where: i.product_id == ^product.id and i.name == ^impl_name and i.team_id == ^team_id
      )

    implementation =
      cond do
        # Linking to existing implementation
        target_impl_name && implementation ->
          implementation

        # Creating new implementation - check for name collision
        existing_impl ->
          throw(
            {:error,
             "Implementation name '#{impl_name}' already exists for this product. Please provide a target_impl_name to link to the existing implementation or choose a different name."}
          )

        # Create new implementation
        true ->
          create_implementation(team_id, product, impl_name, parent_implementation)
      end

    # Track this branch for the implementation
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

    {product, implementation, []}
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
    existing_trackings =
      Repo.all(
        from tb in TrackedBranch,
          where: tb.branch_id == ^branch.id,
          preload: [implementation: :product]
      )

    cond do
      # If states are being pushed but no implementation exists, reject
      states_data && existing_trackings == [] ->
        throw(
          {:error,
           "Cannot push states: branch is not tracked by any implementation. Push specs first or use target_impl_name to link to an existing implementation."}
        )

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

  # Write specs to the database
  # push.INSERT_SPEC.1, push.UPDATE_SPEC.1, push.UPDATE_SPEC.2, push.UPDATE_SPEC.3
  # push.PERMANENCE.1, push.IDEMPOTENCY.1
  defp write_specs(branch, product, specs) do
    now = DateTime.utc_now(:second)

    Enum.reduce(specs, {0, 0}, fn spec_input, {created, updated} ->
      feature = spec_input[:feature] || spec_input["feature"] || %{}
      requirements = spec_input[:requirements] || spec_input["requirements"] || %{}
      meta = spec_input[:meta] || spec_input["meta"] || %{}

      feature_name = feature[:name] || feature["name"]
      feature_description = feature[:description] || feature["description"]
      feature_version = feature[:version] || feature["version"] || "1.0.0"

      path = meta[:path] || meta["path"]
      raw_content = meta[:raw_content] || meta["raw_content"]
      last_seen_commit = meta[:last_seen_commit] || meta["last_seen_commit"]

      # Check if spec already exists for this branch + feature_name
      existing_spec =
        Repo.one(
          from s in Spec,
            where: s.branch_id == ^branch.id and s.feature_name == ^feature_name
        )

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
        requirements: normalize_requirements(requirements)
      }

      if existing_spec do
        # Update existing spec
        # push.UPDATE_SPEC.1
        {:ok, _} =
          Spec.changeset(existing_spec, spec_attrs)
          |> Repo.update()

        {created, updated + 1}
      else
        # Insert new spec
        # push.INSERT_SPEC.1
        {:ok, _} =
          Spec.changeset(%Spec{}, spec_attrs)
          |> Repo.insert()

        {created + 1, updated}
      end
    end)
  end

  # Normalize requirements from various input formats
  defp normalize_requirements(requirements) when is_map(requirements) do
    requirements
    |> Enum.map(fn {acid, defn} ->
      defn_map =
        case defn do
          %{} = map -> map
          req when is_binary(req) -> %{requirement: req}
          _ -> %{requirement: ""}
        end

      {acid, defn_map}
    end)
    |> Map.new()
  end

  defp normalize_requirements(_), do: %{}

  # Write refs to the database
  # push.REFS.1, push.REFS.5, push.REFS.6
  # push.WRITE_REFS.1, push.WRITE_REFS.2, push.WRITE_REFS.3, push.WRITE_REFS.4
  defp write_refs(branch, refs_data, commit_hash) do
    now = DateTime.utc_now(:second)
    data = refs_data[:data] || refs_data["data"] || %{}
    override = refs_data[:override] || refs_data["override"] || false

    # Group refs by feature_name (derived from ACID prefix)
    refs_by_feature =
      data
      |> Enum.group_by(fn {acid, _} -> extract_feature_name_from_acid(acid) end)

    Enum.each(refs_by_feature, fn {feature_name, acid_refs} ->
      refs_map =
        if override do
          # push.REFS.6 - Override replaces everything
          Map.new(acid_refs)
        else
          # push.REFS.5 - Merge: get existing and merge
          existing =
            case Repo.one(
                   from fbr in FeatureBranchRef,
                     where: fbr.branch_id == ^branch.id and fbr.feature_name == ^feature_name
                 ) do
              nil -> %{}
              fbr -> fbr.refs || %{}
            end

          incoming = Map.new(acid_refs)
          Map.merge(existing, incoming)
        end

      # push.WRITE_REFS.4 - Store commit hash
      attrs = %{
        refs: refs_map,
        commit: commit_hash,
        pushed_at: now
      }

      # Upsert the feature_branch_ref
      case Repo.one(
             from fbr in FeatureBranchRef,
               where: fbr.branch_id == ^branch.id and fbr.feature_name == ^feature_name
           ) do
        nil ->
          {:ok, _} =
            FeatureBranchRef.changeset(%FeatureBranchRef{}, %{
              branch_id: branch.id,
              feature_name: feature_name,
              refs: refs_map,
              commit: commit_hash,
              pushed_at: now
            })
            |> Repo.insert()

        existing ->
          {:ok, _} =
            FeatureBranchRef.changeset(existing, attrs)
            |> Repo.update()
      end
    end)
  end

  # Write states to the database
  # push.STATES.1, push.STATES.3
  # push.WRITE_STATES.1, push.WRITE_STATES.2, push.WRITE_STATES.3
  defp write_states(implementation, states_data, _parent_impl_name) do
    data = states_data[:data] || states_data["data"] || %{}
    override = states_data[:override] || states_data["override"] || false

    # Group states by feature_name (derived from ACID prefix)
    states_by_feature =
      data
      |> Enum.group_by(fn {acid, _} -> extract_feature_name_from_acid(acid) end)

    Enum.each(states_by_feature, fn {feature_name, acid_states} ->
      existing_state =
        Repo.one(
          from fis in FeatureImplState,
            where:
              fis.implementation_id == ^implementation.id and
                fis.feature_name == ^feature_name
        )

      states_map =
        cond do
          # push.WRITE_STATES.2 - First write: snapshot from parent then merge
          is_nil(existing_state) and implementation.parent_implementation_id ->
            parent_states =
              case Repo.one(
                     from fis in FeatureImplState,
                       where:
                         fis.implementation_id == ^implementation.parent_implementation_id and
                           fis.feature_name == ^feature_name
                   ) do
                nil -> %{}
                parent -> parent.states || %{}
              end

            incoming = Map.new(acid_states)
            Map.merge(parent_states, incoming)

          # push.WRITE_STATES.3 - Subsequent writes: patch existing
          existing_state != nil and not override ->
            incoming = Map.new(acid_states)
            Map.merge(existing_state.states || %{}, incoming)

          # Override mode
          override ->
            Map.new(acid_states)

          # First write, no parent
          true ->
            Map.new(acid_states)
        end

      attrs = %{
        states: states_map
      }

      if existing_state do
        {:ok, _} =
          FeatureImplState.changeset(existing_state, attrs)
          |> Repo.update()
      else
        {:ok, _} =
          FeatureImplState.changeset(%FeatureImplState{}, %{
            implementation_id: implementation.id,
            feature_name: feature_name,
            states: states_map
          })
          |> Repo.insert()
      end
    end)
  end

  # Extract feature name from ACID (e.g., "my-feature.COMP.1" -> "my-feature")
  defp extract_feature_name_from_acid(acid) when is_binary(acid) do
    case String.split(acid, ".", parts: 2) do
      [feature_name, _] -> feature_name
      _ -> acid
    end
  end

  defp extract_feature_name_from_acid(_), do: "unknown"
end
