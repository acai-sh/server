defmodule Acai.Services.Push do
  @moduledoc """
  Service module for handling push operations.

  This module orchestrates the full push flow including:
  - Branch resolution/creation
  - Product/implementation resolution
  - Spec writes
  - Ref writes
  - Implementation linking

  All operations are wrapped in a transaction for atomicity.

  See push.TX.1, push.feature.yaml
  """

  import Ecto.Query

  alias Acai.Repo
  alias Acai.Teams.AccessToken
  alias Acai.Implementations.{Branch, Implementation, TrackedBranch}
  alias Acai.Products.Product
  alias Acai.Specs.{Spec, FeatureBranchRef}
  alias AcaiWeb.Api.RejectionLog
  alias AcaiWeb.Api.Operations

  @push_endpoint "/api/v1/push"

  @normalized_param_keys %{
    "repo_uri" => :repo_uri,
    "branch_name" => :branch_name,
    "commit_hash" => :commit_hash,
    "specs" => :specs,
    "references" => :references,
    "product_name" => :product_name,
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

  @write_scopes ["specs:write", "refs:write", "impls:write"]

  @doc """
  Executes a push operation.

  Returns {:ok, response_map} on success or {:error, reason} on failure.

  ## Parameters
    - token: The authenticated AccessToken
    - params: The validated push request parameters
  """
  def execute(%AccessToken{} = token, params) do
    # push.REQUEST.4, push.REQUEST.5, push.REQUEST.7, push.REQUEST.8
    # Normalize params once at entry point to avoid repeated atom/string key lookups
    normalized_params = normalize_params(params)

    # Check required scopes based on what parts of the request are present
    with :ok <- check_scopes(token, normalized_params),
         :ok <- validate_push_request(token, normalized_params) do
      Repo.run_transaction(fn ->
        do_push(token, normalized_params)
      end)
    end
  end

  # push.REQUEST.4, push.REQUEST.5, push.REQUEST.7, push.REQUEST.8
  # Normalize incoming params to use atom keys consistently throughout the service.
  # This eliminates the need for defensive `params[:key] || params["key"]` lookups.
  defp normalize_params(params) when is_struct(params) do
    params
    |> Map.from_struct()
    |> normalize_params()
  end

  defp normalize_params(params) when is_map(params) do
    params
    |> normalize_map_keys()
    |> normalize_nested_params()
  end

  defp normalize_params(params), do: params

  # Convert string keys to atom keys for top-level params only.
  # Nested maps (specs, references) are handled separately to preserve
  # user-defined string keys in data payloads (like ACIDs).
  defp normalize_map_keys(map) when is_map(map) do
    Enum.reduce(map, %{}, fn {key, value}, acc ->
      Map.put(acc, normalize_param_key(key), value)
    end)
  end

  defp normalize_map_keys(nil), do: nil

  defp normalize_param_key(key) when is_binary(key), do: Map.get(@normalized_param_keys, key, key)
  defp normalize_param_key(key), do: key

  # Normalize nested structures in specs and references
  defp normalize_nested_params(params) do
    params
    |> Map.update(:specs, [], &normalize_specs/1)
    |> Map.update(:references, nil, &normalize_map_keys/1)
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

  # push.AUTH.2, push.AUTH.3, push.AUTH.4
  # Convert token scopes to a set-like structure once and derive all checks from it
  defp check_scopes(token, params) do
    # Build a scope lookup map once to avoid 4 separate token_has_scope? calls
    scope_map = build_scope_map(token)

    specs = params[:specs] || []
    refs = params[:references]
    has_specs = specs != []

    refs_only_impl_request? =
      refs != nil and has_specs == false and refs_only_impl_context_requested?(params)

    tracked_branch_specs_only? = has_specs and branch_is_already_tracked?(token.team_id, params)

    # If pushing specs, need specs:write
    cond do
      has_specs and not scope_map["specs:write"] ->
        {:error, {:forbidden, "Token missing required scope: specs:write"}}

      refs != nil and not scope_map["refs:write"] ->
        {:error, {:forbidden, "Token missing required scope: refs:write"}}

      # push.AUTH.4
      refs_only_impl_request? and not scope_map["impls:write"] ->
        {:error, {:forbidden, "Token missing required scope: impls:write"}}

      has_specs and not tracked_branch_specs_only? and not scope_map["impls:write"] ->
        {:error, {:forbidden, "Token missing required scope: impls:write"}}

      true ->
        :ok
    end
  end

  # push.AUTH.2, push.AUTH.3, push.AUTH.4
  # Build a map of scope -> boolean for O(1) lookups instead of multiple function calls
  defp build_scope_map(%AccessToken{} = token) do
    scopes = MapSet.new(token.scopes || [])

    Map.new(@write_scopes, fn scope -> {scope, MapSet.member?(scopes, scope)} end)
  end

  # push.AUTH.4
  defp refs_only_impl_context_requested?(params) do
    not is_nil(params[:product_name]) and
      (not is_nil(params[:target_impl_name]) or not is_nil(params[:parent_impl_name]))
  end

  # push.AUTH.4
  defp branch_is_already_tracked?(team_id, params) do
    case {params[:repo_uri], params[:branch_name]} do
      {repo_uri, branch_name} when is_binary(repo_uri) and is_binary(branch_name) ->
        Repo.one(
          from b in Branch,
            join: tb in TrackedBranch,
            on: tb.branch_id == b.id,
            where:
              b.team_id == ^team_id and
                b.repo_uri == ^repo_uri and
                b.branch_name == ^branch_name,
            select: tb.branch_id,
            limit: 1
        ) != nil

      _ ->
        false
    end
  end

  # push.REQUEST.10, push.VALIDATION.6, push.ABUSE.2
  defp validate_push_request(token, params) do
    specs = params[:specs] || []

    with :ok <- validate_duplicate_feature_names(token, specs, params),
         :ok <- validate_spec_product_name(token, specs, params),
         :ok <- validate_semantic_caps(token, params) do
      :ok
    end
  end

  # push.REQUEST.10
  defp validate_duplicate_feature_names(token, specs, params) do
    feature_names = extract_feature_names_from_specs(specs)

    case Enum.find(feature_names, fn feature_name ->
           feature_name && Enum.count(feature_names, &(&1 == feature_name)) > 1
         end) do
      nil ->
        :ok

      duplicate_feature_name ->
        reject_push_request(
          token,
          "Push rejected: specs contain duplicate feature.name '#{duplicate_feature_name}'.",
          params,
          spec_count: length(specs)
        )
    end
  end

  # push.VALIDATION.6
  defp validate_spec_product_name(token, specs, params) do
    case {specs, params[:product_name], extract_product_names_from_specs(specs)} do
      {[], _, _} ->
        :ok

      {_, nil, _} ->
        :ok

      {_, product_name, [shared_product_name]} when product_name == shared_product_name ->
        :ok

      {_, product_name, [shared_product_name]} ->
        reject_push_request(
          token,
          "product_name '#{product_name}' must match pushed specs product '#{shared_product_name}'",
          params,
          product_name: product_name
        )

      {_, _product_name, _} ->
        :ok
    end
  end

  # push.ABUSE.2-1, push.ABUSE.2-2, push.ABUSE.2-3, push.ABUSE.2-4, push.ABUSE.2-5,
  # push.ABUSE.2-6, push.ABUSE.2-7, push.ABUSE.2-8
  defp validate_semantic_caps(token, params) do
    caps = Operations.semantic_caps(:push)
    specs = params[:specs] || []

    cond do
      exceeds_cap?(length(specs), caps[:max_specs]) ->
        reject_push_request(token, "Push rejected: too many specs in one push.", params,
          spec_count: length(specs),
          max_specs: caps[:max_specs]
        )

      exceeds_cap?(references_entry_count(params[:references]), caps[:max_references]) ->
        reject_push_request(
          token,
          "Push rejected: too many reference entries in one push.",
          params,
          reference_count: references_entry_count(params[:references]),
          max_references: caps[:max_references]
        )

      violation = spec_cap_violation(specs, caps) ->
        reject_push_request(token, violation, params, spec_count: length(specs))

      exceeds_string_cap?(params[:repo_uri], caps[:max_repo_uri_length]) ->
        reject_push_request(
          token,
          "Push rejected: repo_uri exceeds the configured maximum length.",
          params,
          repo_uri_length: string_length(params[:repo_uri]),
          max_repo_uri_length: caps[:max_repo_uri_length]
        )

      true ->
        :ok
    end
  end

  defp spec_cap_violation(specs, caps) do
    Enum.find_value(specs, fn spec ->
      requirements = spec[:requirements] || %{}

      cond do
        exceeds_cap?(map_size(requirements), caps[:max_requirements_per_spec]) ->
          "Push rejected: a spec exceeded the configured requirement count."

        exceeds_string_cap?(
          spec_in(spec, [:meta, :raw_content]),
          caps[:max_raw_content_bytes],
          :byte_size
        ) ->
          "Push rejected: meta.raw_content exceeds the configured maximum length."

        exceeds_string_cap?(
          spec_in(spec, [:feature, :description]),
          caps[:max_feature_description_length]
        ) ->
          "Push rejected: feature.description exceeds the configured maximum length."

        exceeds_string_cap?(spec_in(spec, [:meta, :path]), caps[:max_meta_path_length]) ->
          "Push rejected: meta.path exceeds the configured maximum length."

        requirement_over_limit =
            invalid_requirement_text?(requirements, caps[:max_requirement_string_length]) ->
          requirement_over_limit

        true ->
          nil
      end
    end)
  end

  defp invalid_requirement_text?(_requirements, nil), do: nil

  defp invalid_requirement_text?(requirements, max_length) when is_integer(max_length) do
    Enum.find_value(requirements, fn {_acid, definition} ->
      requirement_text =
        cond do
          is_map(definition) ->
            Map.get(definition, :requirement) ||
              Map.get(definition, "requirement") ||
              Map.get(definition, :definition) ||
              Map.get(definition, "definition") ||
              ""

          is_binary(definition) ->
            definition

          true ->
            ""
        end

      if string_length(requirement_text) > max_length do
        "Push rejected: a requirement string exceeds the configured maximum length."
      else
        nil
      end
    end)
  end

  defp invalid_requirement_text?(_requirements, _max_length), do: nil

  defp references_entry_count(nil), do: 0

  defp references_entry_count(references) when is_map(references) do
    references
    |> Map.get(:data, %{})
    |> case do
      data when is_map(data) -> map_size(data)
      _ -> 0
    end
  end

  defp references_entry_count(_), do: 0

  defp exceeds_cap?(_value, nil), do: false
  defp exceeds_cap?(value, cap) when is_integer(cap), do: value > cap
  defp exceeds_cap?(_value, _cap), do: false

  defp exceeds_string_cap?(value, cap), do: exceeds_string_cap?(value, cap, :length)

  defp exceeds_string_cap?(value, cap, mode)

  defp exceeds_string_cap?(nil, _cap, _mode), do: false

  defp exceeds_string_cap?(value, cap, mode) when is_integer(cap) do
    case normalized_string_length(value, mode) do
      nil -> false
      length -> length > cap
    end
  end

  defp exceeds_string_cap?(_value, _cap, _mode), do: false

  defp spec_in(spec, path) do
    Enum.reduce(path, spec, fn key, acc ->
      case acc do
        %{} = map -> Map.get(map, key) || Map.get(map, to_string(key))
        _ -> nil
      end
    end)
  end

  defp string_length(nil, :byte_size), do: nil
  defp string_length(value, :byte_size) when is_binary(value), do: byte_size(value)
  defp string_length(value, :byte_size), do: value |> to_string() |> byte_size()

  defp string_length(nil), do: nil
  defp string_length(value) when is_binary(value), do: String.length(value)
  defp string_length(value), do: value |> to_string() |> String.length()

  defp normalized_string_length(value, :byte_size), do: string_length(value, :byte_size)
  defp normalized_string_length(value, :length), do: string_length(value)

  defp reject_push_request(token, reason, params, extra) do
    log_push_rejection(token, :abuse, reason, params, extra)
    {:error, reason}
  end

  defp log_push_rejection(token, category, reason, params, extra) do
    payload =
      %{
        request_id: nil,
        endpoint: @push_endpoint,
        method: "POST",
        category: category,
        reason: reason,
        team_id: token.team_id,
        token_id: token.id,
        repo_uri: params[:repo_uri],
        branch_name: params[:branch_name],
        spec_count: length(params[:specs] || []),
        reference_count: references_entry_count(params[:references])
      }
      |> Map.merge(Map.new(extra))
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    # push.ABUSE.5
    RejectionLog.emit(payload)
  end

  defp do_push(token, params) do
    try do
      do_push_internal(token, params)
    catch
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_push_internal(token, params) do
    # push.REQUEST.4, push.REQUEST.5, push.REQUEST.7, push.REQUEST.8
    # Params are already normalized to use atom keys at entry point
    team_id = token.team_id
    repo_uri = params[:repo_uri]
    branch_name = params[:branch_name]
    commit_hash = params[:commit_hash]
    specs = params[:specs] || []
    refs_data = params[:references]
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

    # Step 2: Resolve implementation context and enforce request-matrix rules
    # push.NEW_IMPLS.3, push.NEW_IMPLS.4, push.NEW_IMPLS.6, push.LINK_IMPLS.1, push.LINK_IMPLS.4,
    # push.EXISTING_IMPLS.2, push.EXISTING_IMPLS.3, push.EXISTING_IMPLS.4, push.IDEMPOTENCY.5
    {product, implementation, warnings} =
      resolve_push_context(
        token,
        team_id,
        branch,
        specs,
        refs_data,
        target_impl_name,
        parent_impl_name,
        params
      )

    # push.IDEMPOTENCY.5, push.IDEMPOTENCY.5-1
    maybe_validate_existing_parent!(token, implementation, parent_impl_name, params)

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

    {:ok, build_response(branch, product, implementation, specs_created, specs_updated, warnings)}
  end

  # push.REFS.3, push.REFS.4, push.WRITE_REFS.1, push.WRITE_REFS.2, push.WRITE_REFS.3
  defp maybe_write_refs(_branch, nil, _commit_hash), do: :ok

  defp maybe_write_refs(branch, refs_data, commit_hash) do
    write_refs(branch, refs_data, commit_hash)
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

  defp maybe_raise_name_collision!(existing_impl, implementation_name) do
    if existing_impl do
      throw(
        {:error,
         "Implementation name '#{implementation_name}' already exists for this product. Please provide a target_impl_name to link to the existing implementation or choose a different name."}
      )
    end
  end

  # push.NEW_IMPLS.4, push.VALIDATION.3, push.VALIDATION.4
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

  # push.NEW_IMPLS.3, push.NEW_IMPLS.4, push.NEW_IMPLS.6, push.LINK_IMPLS.1, push.LINK_IMPLS.4
  # push.EXISTING_IMPLS.2, push.EXISTING_IMPLS.3, push.EXISTING_IMPLS.4, push.IDEMPOTENCY.5
  defp resolve_push_context(
         token,
         team_id,
         branch,
         specs,
         refs_data,
         target_impl_name,
         parent_impl_name,
         params
       ) do
    cond do
      specs != [] ->
        handle_specs_push(
          token,
          team_id,
          branch,
          specs,
          params[:product_name],
          target_impl_name,
          parent_impl_name,
          params
        )

      true ->
        handle_no_specs_push(
          token,
          team_id,
          branch,
          refs_data,
          params[:product_name],
          target_impl_name,
          parent_impl_name,
          params
        )
    end
  end

  defp handle_no_specs_push(
         token,
         team_id,
         branch,
         refs_data,
         product_name,
         target_impl_name,
         parent_impl_name,
         params
       ) do
    existing_trackings = implementation_trackings_for_branch(branch)

    cond do
      existing_trackings != [] ->
        resolve_existing_implementation(team_id, branch, target_impl_name)

      refs_data != nil ->
        handle_untracked_refs_only_push(
          token,
          team_id,
          branch,
          product_name,
          target_impl_name,
          parent_impl_name,
          params
        )

      true ->
        {nil, nil, []}
    end
  end

  # push.NEW_IMPLS.6, push.NEW_IMPLS.7, push.LINK_IMPLS.1, push.LINK_IMPLS.4, push.LINK_IMPLS.5
  # push.VALIDATION.7, push.VALIDATION.8, push.VALIDATION.9
  defp handle_untracked_refs_only_push(
         token,
         team_id,
         branch,
         product_name,
         target_impl_name,
         parent_impl_name,
         params
       ) do
    cond do
      is_nil(product_name) and (not is_nil(target_impl_name) or not is_nil(parent_impl_name)) ->
        {:error, reason} =
          reject_push_request(
            token,
            "Refs-only pushes that create or link an implementation require product_name.",
            params,
            branch_name: branch.branch_name
          )

        throw({:error, reason})

      not is_nil(parent_impl_name) and is_nil(target_impl_name) ->
        {:error, reason} =
          reject_push_request(
            token,
            "Refs-only pushes that create a new child implementation require target_impl_name and parent_impl_name.",
            params,
            branch_name: branch.branch_name
          )

        throw({:error, reason})

      not is_nil(product_name) and not is_nil(target_impl_name) and not is_nil(parent_impl_name) ->
        handle_untracked_child_push(
          token,
          team_id,
          branch,
          product_name,
          target_impl_name,
          parent_impl_name,
          params
        )

      not is_nil(product_name) and not is_nil(target_impl_name) ->
        handle_untracked_refs_only_link_push(
          token,
          team_id,
          branch,
          product_name,
          target_impl_name,
          params
        )

      not is_nil(product_name) or not is_nil(target_impl_name) or not is_nil(parent_impl_name) ->
        {:error, reason} =
          reject_push_request(
            token,
            "Refs-only push inputs must satisfy either the child-implementation or link-implementation rule set.",
            params,
            branch_name: branch.branch_name
          )

        throw({:error, reason})

      true ->
        {nil, nil, []}
    end
  end

  # push.IDEMPOTENCY.5, push.IDEMPOTENCY.5-1
  defp maybe_validate_existing_parent!(token, implementation, parent_impl_name, params) do
    if implementation && parent_impl_name do
      implementation = Repo.preload(implementation, :parent_implementation)

      case implementation.parent_implementation do
        %{name: ^parent_impl_name} ->
          :ok

        _ ->
          {:error, reason} =
            reject_push_request(
              token,
              "Parent implementation cannot be changed via push.",
              params,
              implementation_name: implementation.name
            )

          throw({:error, reason})
      end
    else
      :ok
    end
  end

  defp ensure_product!(team_id, product_name) do
    case find_product(team_id, product_name) do
      nil ->
        {:ok, product} =
          Product.changeset(%Product{}, %{name: product_name, team_id: team_id}) |> Repo.insert()

        product

      existing ->
        existing
    end
  end

  defp fetch_parent_implementation!(team_id, product_id, parent_impl_name) do
    case Repo.one(
           from i in Implementation,
             where:
               i.team_id == ^team_id and i.product_id == ^product_id and
                 i.name == ^parent_impl_name
         ) do
      nil ->
        throw({:error, "Parent implementation '#{parent_impl_name}' not found"})

      parent ->
        parent
    end
  end

  defp handle_specs_push(
         token,
         team_id,
         branch,
         specs,
         product_name,
         target_impl_name,
         parent_impl_name,
         params
       ) do
    product_names = extract_product_names_from_specs(specs)

    if length(product_names) > 1 do
      reject_push_request(
        token,
        "Push rejected: specs span multiple products (#{Enum.join(product_names, ", ")}). All specs must belong to the same product.",
        params,
        spec_count: length(specs)
      )
      |> case do
        {:error, reason} -> throw({:error, reason})
      end
    end

    product_name = product_name || List.first(product_names)
    existing_trackings = implementation_trackings_for_branch(branch)

    cond do
      existing_trackings != [] ->
        handle_tracked_branch_push(
          token,
          team_id,
          existing_trackings,
          target_impl_name,
          specs,
          params
        )

      parent_impl_name != nil ->
        handle_untracked_child_push(
          token,
          team_id,
          branch,
          product_name,
          target_impl_name,
          parent_impl_name,
          params
        )

      true ->
        handle_untracked_branch_link_or_create_push(
          token,
          team_id,
          branch,
          product_name,
          target_impl_name,
          params
        )
    end
  end

  # Handle push when branch is already tracked
  # push.EXISTING_IMPLS.1, push.EXISTING_IMPLS.2, push.EXISTING_IMPLS.3, push.EXISTING_IMPLS.4
  defp handle_tracked_branch_push(
         _token,
         _team_id,
         existing_trackings,
         target_impl_name,
         specs,
         _params
       ) do
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

    if target_impl_name && implementation.name != target_impl_name do
      throw(
        {:error,
         "Branch is already tracked by implementation '#{implementation.name}' but target_impl_name '#{target_impl_name}' was specified"}
      )
    end

    spec_product_names = extract_product_names_from_specs(specs)

    if spec_product_names != [] and hd(spec_product_names) != implementation.product.name do
      throw(
        {:error,
         "All specs must belong to the same product as the target implementation '#{implementation.name}' (product: '#{implementation.product.name}')"}
      )
    end

    {implementation.product, implementation, []}
  end

  # Handle push when branch is not tracked and the request explicitly wants a new child implementation.
  # push.NEW_IMPLS.6, push.NEW_IMPLS.6-1, push.NEW_IMPLS.6-2
  defp handle_untracked_child_push(
         _token,
         team_id,
         branch,
         product_name,
         target_impl_name,
         parent_impl_name,
         _params
       ) do
    product = ensure_product!(team_id, product_name)
    parent_impl = fetch_parent_implementation!(team_id, product.id, parent_impl_name)

    impl_name = target_impl_name || branch.branch_name

    existing_impl_for_collision =
      fetch_implementation_name_collision(team_id, product.id, impl_name)

    maybe_raise_name_collision!(existing_impl_for_collision, impl_name)

    implementation = create_implementation(team_id, product, impl_name, parent_impl)
    maybe_track_branch(implementation, branch)

    {product, implementation, []}
  end

  # push.LINK_IMPLS.5, push.VALIDATION.9
  defp handle_untracked_refs_only_link_push(
         token,
         team_id,
         branch,
         product_name,
         target_impl_name,
         params
       ) do
    product = ensure_product!(team_id, product_name)

    {target_impl, _parent_impl} =
      fetch_implementations_consolidated(team_id, product, branch, target_impl_name, nil)

    case target_impl do
      nil ->
        {:error, reason} =
          reject_push_request(
            token,
            "Refs-only pushes with product_name and target_impl_name must resolve to an existing implementation unless parent_impl_name is also provided.",
            params,
            branch_name: branch.branch_name,
            product_name: product_name,
            target_impl_name: target_impl_name
          )

        throw({:error, reason})

      implementation ->
        maybe_track_branch(implementation, branch)
        {product, implementation, []}
    end
  end

  # Handle push when branch is not tracked and the request may link to an existing implementation.
  # push.NEW_IMPLS.1, push.NEW_IMPLS.3, push.NEW_IMPLS.5, push.LINK_IMPLS.1, push.LINK_IMPLS.3
  defp handle_untracked_branch_link_or_create_push(
         _token,
         team_id,
         branch,
         product_name,
         target_impl_name,
         _params
       ) do
    product = ensure_product!(team_id, product_name)

    {target_impl, _parent_impl} =
      fetch_implementations_consolidated(team_id, product, branch, target_impl_name, nil)

    impl_name = target_impl_name || branch.branch_name

    existing_impl_for_collision =
      if is_nil(target_impl_name) do
        fetch_implementation_name_collision(team_id, product.id, impl_name)
      else
        nil
      end

    implementation =
      cond do
        target_impl_name && target_impl ->
          target_impl

        existing_impl_for_collision ->
          maybe_raise_name_collision!(existing_impl_for_collision, impl_name)

        true ->
          create_implementation(team_id, product, impl_name, nil)
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
          # push.NEW_IMPLS.1, push.NEW_IMPLS.1-1
          nil ->
            nil

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
  defp resolve_existing_implementation(_team_id, branch, target_impl_name) do
    existing_trackings = implementation_trackings_for_branch(branch)

    cond do
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
        throw({:error, changeset})
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
