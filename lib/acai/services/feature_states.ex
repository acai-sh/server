defmodule Acai.Services.FeatureStates do
  @moduledoc """
  Service module for PATCH /api/v1/feature-states.

  See feature-states.WRITE.1 through feature-states.WRITE.7
  """

  alias Acai.Repo
  alias Acai.Specs
  alias Acai.Teams.Team
  alias AcaiWeb.Api.Operations

  @valid_statuses [nil, "assigned", "blocked", "incomplete", "completed", "rejected", "accepted"]

  @doc """
  Resolves the requested feature state write and persists the merged local state row.
  """
  def execute(%Team{} = team, attrs) do
    # feature-states.REQUEST.1, feature-states.REQUEST.2, feature-states.REQUEST.3, feature-states.REQUEST.4
    with {:ok, parsed} <- parse_request(attrs),
         :ok <- validate_semantic_caps(parsed),
         {:ok, context} <- resolve_context(team, parsed),
         {:ok, result} <- persist_state(context, parsed) do
      {:ok, result}
    end
  end

  defp parse_request(attrs) when is_map(attrs) do
    with {:ok, product_name} <- required_string(attrs, "product_name"),
         {:ok, feature_name} <- required_string(attrs, "feature_name"),
         {:ok, implementation_name} <- required_string(attrs, "implementation_name"),
         {:ok, states} <- parse_states(attrs) do
      {:ok,
       %{
         product_name: product_name,
         feature_name: feature_name,
         implementation_name: implementation_name,
         states: states
       }}
    end
  end

  defp parse_request(_attrs), do: {:error, {"feature-states payload must be a JSON object", %{}}}

  defp parse_states(attrs) do
    case lookup(attrs, "states") do
      states when is_map(states) and map_size(states) > 0 ->
        {:ok, states}

      states when is_map(states) ->
        {:error,
         {"states must contain at least one ACID entry", %{states_count: map_size(states)}}}

      nil ->
        {:error, {"states is required", %{}}}

      _other ->
        {:error, {"states must be an object", %{}}}
    end
  end

  # feature-states.REQUEST.1, feature-states.REQUEST.2, feature-states.REQUEST.3, feature-states.VALIDATION.1
  defp required_string(attrs, key) do
    case lookup(attrs, key) do
      nil ->
        {:error, {"#{key} is required", %{}}}

      value when is_binary(value) ->
        trimmed = String.trim(value)

        if trimmed == "" do
          {:error, {"#{key} cannot be blank", %{}}}
        else
          {:ok, trimmed}
        end

      _value ->
        {:error, {"#{key} must be a string", %{}}}
    end
  end

  defp validate_semantic_caps(%{states: states}) do
    # feature-states.ABUSE.2-1, feature-states.ABUSE.2-2, feature-states.ABUSE.2-3, feature-states.ABUSE.4-2
    caps = Operations.semantic_caps(:feature_states)
    max_states = Map.get(caps, :max_states)
    max_comment_length = Map.get(caps, :max_comment_length)

    cond do
      is_integer(max_states) and map_size(states) > max_states ->
        {:error,
         {"feature-states request exceeds the configured maximum number of ACIDs",
          %{
            states_count: map_size(states),
            max_states: max_states
          }}}

      violation = comment_cap_violation(states, max_comment_length) ->
        {:error, {violation, %{max_comment_length: max_comment_length}}}

      true ->
        :ok
    end
  end

  defp comment_cap_violation(_states, nil), do: nil

  defp comment_cap_violation(states, max_comment_length) when is_integer(max_comment_length) do
    Enum.find_value(states, fn {acid, state} ->
      comment = state_comment(state)

      if is_binary(comment) and String.length(comment) > max_comment_length do
        "State comment for #{acid} exceeds the configured maximum length"
      else
        nil
      end
    end)
  end

  defp comment_cap_violation(_states, _max_comment_length), do: nil

  defp resolve_context(team, %{
         product_name: product_name,
         feature_name: feature_name,
         implementation_name: implementation_name
       }) do
    # feature-states.RESPONSE.5, feature-states.WRITE.1, feature-states.WRITE.2, feature-states.WRITE.3
    Specs.get_feature_state_write_context(team, product_name, feature_name, implementation_name)
  end

  defp persist_state(
         %{
           product: product,
           feature_name: feature_name,
           implementation: implementation,
           resolved_acids: resolved_acids
         },
         %{states: states}
       ) do
    # feature-states.RESPONSE.1, feature-states.RESPONSE.2, feature-states.RESPONSE.3, feature-states.RESPONSE.4
    with {:ok, validated_states, warnings} <-
           validate_states(feature_name, states, resolved_acids),
         {:ok, _state} <- write_state_row(feature_name, implementation, validated_states) do
      {:ok,
       %{
         product_name: product.name,
         feature_name: feature_name,
         implementation_name: implementation.name,
         implementation_id: to_string(implementation.id),
         states_written: map_size(validated_states),
         warnings: warnings
       }}
    end
  end

  defp validate_states(feature_name, states, resolved_acids) do
    # feature-states.REQUEST.4-1, feature-states.REQUEST.4-2, feature-states.REQUEST.4-3, feature-states.REQUEST.5, feature-states.REQUEST.6
    Enum.reduce_while(states, {:ok, %{}, []}, fn {acid, state}, {:ok, acc_states, acc_warnings} ->
      with :ok <- validate_acid(acid, feature_name),
           {:ok, normalized_state} <- validate_state_object(acid, state) do
        warnings =
          if MapSet.member?(resolved_acids, acid) do
            acc_warnings
          else
            ["Persisted dangling state for #{acid}" | acc_warnings]
          end

        {:cont, {:ok, Map.put(acc_states, acid, normalized_state), warnings}}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, states, warnings} -> {:ok, states, Enum.reverse(warnings)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp validate_acid(acid, feature_name) when is_binary(acid) do
    prefix = feature_name <> "."

    cond do
      not String.starts_with?(acid, prefix) ->
        {:error, "All state ACIDs must start with #{prefix}"}

      not String.contains?(String.replace_prefix(acid, prefix, ""), ".") ->
        {:error, "State ACIDs must be full ACID strings"}

      true ->
        :ok
    end
  end

  defp validate_acid(_acid, _feature_name), do: {:error, "State ACIDs must be strings"}

  defp validate_state_object(acid, state) when is_map(state) do
    with {:ok, status} <- validate_status(acid, lookup(state, "status", :missing)),
         {:ok, comment} <- validate_comment(acid, lookup(state, "comment")) do
      {:ok, Map.merge(%{"status" => status}, maybe_put_comment(%{}, comment))}
    end
  end

  defp validate_state_object(_acid, _state), do: {:error, "Each state entry must be an object"}

  defp validate_status(_acid, :missing), do: {:error, "Each state entry requires a status"}
  defp validate_status(_acid, nil), do: {:ok, nil}
  defp validate_status(_acid, status) when status in @valid_statuses, do: {:ok, status}
  defp validate_status(_acid, _status), do: {:error, "Invalid state status value"}

  defp validate_comment(_acid, nil), do: {:ok, nil}
  defp validate_comment(_acid, comment) when is_binary(comment), do: {:ok, comment}
  defp validate_comment(_acid, _comment), do: {:error, "State comment must be a string"}

  defp maybe_put_comment(map, nil), do: map
  defp maybe_put_comment(map, comment), do: Map.put(map, "comment", comment)

  defp state_comment(state) when is_map(state),
    do: lookup(state, "comment")

  defp state_comment(_), do: nil

  defp lookup(attrs, key, default) when is_map(attrs) and is_binary(key) do
    cond do
      Map.has_key?(attrs, key) ->
        Map.get(attrs, key)

      key == "product_name" and Map.has_key?(attrs, :product_name) ->
        Map.get(attrs, :product_name)

      key == "feature_name" and Map.has_key?(attrs, :feature_name) ->
        Map.get(attrs, :feature_name)

      key == "implementation_name" and Map.has_key?(attrs, :implementation_name) ->
        Map.get(attrs, :implementation_name)

      key == "states" and Map.has_key?(attrs, :states) ->
        Map.get(attrs, :states)

      key == "status" and Map.has_key?(attrs, :status) ->
        Map.get(attrs, :status)

      key == "comment" and Map.has_key?(attrs, :comment) ->
        Map.get(attrs, :comment)

      true ->
        default
    end
  end

  defp lookup(attrs, key), do: lookup(attrs, key, nil)

  defp write_state_row(feature_name, implementation, incoming_states) do
    # feature-states.WRITE.2, feature-states.WRITE.3, feature-states.WRITE.4, feature-states.WRITE.5, feature-states.WRITE.7
    existing_state = Specs.get_feature_impl_state(feature_name, implementation)

    local_base_states =
      case existing_state do
        nil ->
          case implementation.parent_implementation_id do
            nil ->
              %{}

            parent_id ->
              case Repo.get(Acai.Implementations.Implementation, parent_id) do
                nil ->
                  %{}

                parent_impl ->
                  case Specs.get_feature_impl_state(feature_name, parent_impl) do
                    nil -> %{}
                    %Acai.Specs.FeatureImplState{states: states} -> states || %{}
                  end
              end
          end

        %Acai.Specs.FeatureImplState{states: states} ->
          states || %{}
      end

    merged_states = Map.merge(local_base_states, incoming_states)

    Specs.upsert_feature_impl_state(feature_name, implementation, %{states: merged_states})
  end
end
