defmodule AcaiWeb.Api.FeatureContextController do
  @moduledoc """
  Read-only API controller for canonical feature context.
  """

  use AcaiWeb.Api.Controller

  alias Acai.Specs
  alias AcaiWeb.Api.Schemas.ReadSchemas

  @valid_statuses [nil, "assigned", "blocked", "incomplete", "completed", "rejected", "accepted"]

  # feature-context.ENDPOINT.1, feature-context.ENDPOINT.2
  tags(["Actions"])
  security([%{"bearerAuth" => []}])

  operation(:show,
    summary: "Read canonical feature context",
    description:
      "Return the canonical spec, resolved states, and refs for one feature in one implementation.",
    parameters: [
      # feature-context.REQUEST.1
      OpenApiSpex.Operation.parameter(:product_name, :query, :string, "Product name",
        required: true
      ),
      # feature-context.REQUEST.2
      OpenApiSpex.Operation.parameter(:feature_name, :query, :string, "Feature name",
        required: true
      ),
      OpenApiSpex.Operation.parameter(
        :implementation_name,
        :query,
        :string,
        "Implementation name",
        # feature-context.REQUEST.3
        required: true
      ),
      OpenApiSpex.Operation.parameter(
        :include_refs,
        :query,
        :boolean,
        "Include per-ACID ref details",
        required: false
      ),
      OpenApiSpex.Operation.parameter(
        :include_dangling_states,
        :query,
        :boolean,
        "Include dangling stored states",
        required: false
      ),
      OpenApiSpex.Operation.parameter(
        :include_deprecated,
        :query,
        :boolean,
        "Include deprecated ACIDs",
        required: false
      ),
      OpenApiSpex.Operation.parameter(
        :statuses,
        :query,
        %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}},
        "Repeated status filter values; the literal string `null` means a null status",
        required: false
      )
    ],
    responses: [
      ok: {"Feature context", "application/json", ReadSchemas.FeatureContextResponse},
      unauthorized: {"Unauthorized", "application/json", ReadSchemas.ErrorResponse},
      forbidden: {"Forbidden", "application/json", ReadSchemas.ErrorResponse},
      not_found: {"Not found", "application/json", ReadSchemas.ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ReadSchemas.ErrorResponse}
    ]
  )

  # feature-context.RESPONSE.1, feature-context.RESPONSE.13, feature-context.RESPONSE.14, feature-context.RESPONSE.15, feature-context.RESPONSE.16
  def show(conn, params) do
    token = conn.assigns.current_token
    team = conn.assigns.current_team
    request_params = merged_params(conn, params)

    # feature-context.AUTH.2, feature-context.RESPONSE.13, feature-context.RESPONSE.14, feature-context.RESPONSE.15, feature-context.RESPONSE.16
    with :ok <- ensure_scope(token, "impls:read"),
         :ok <- ensure_scope(token, "specs:read"),
         :ok <- ensure_scope(token, "states:read"),
         :ok <- ensure_scope(token, "refs:read"),
         {:ok, parsed} <- parse_params(request_params),
         {:ok, payload} <-
           Specs.get_feature_context(
             team,
             parsed.product_name,
             parsed.feature_name,
             parsed.implementation_name,
             include_refs: parsed.include_refs,
             include_dangling_states: parsed.include_dangling_states,
             include_deprecated: parsed.include_deprecated,
             statuses: parsed.statuses
           ) do
      render_data(conn, payload)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_scope(token, scope) do
    if Acai.Teams.token_has_scope?(token, scope),
      do: :ok,
      else: {:error, {:forbidden, "Token missing required scope: #{scope}"}}
  end

  defp merged_params(conn, params) do
    conn.query_params
    |> Map.merge(conn.body_params || %{})
    |> Map.merge(params || %{})
  end

  defp parse_params(params) do
    # feature-context.REQUEST.1, feature-context.REQUEST.2, feature-context.REQUEST.3, feature-context.REQUEST.4, feature-context.REQUEST.5, feature-context.REQUEST.6, feature-context.REQUEST.7, feature-context.REQUEST.7-1
    with {:ok, product_name} <- required_string(params, "product_name"),
         {:ok, feature_name} <- required_string(params, "feature_name"),
         {:ok, implementation_name} <- required_string(params, "implementation_name"),
         {:ok, include_refs} <- optional_bool(params, "include_refs", false),
         {:ok, include_dangling_states} <- optional_bool(params, "include_dangling_states", false),
         {:ok, include_deprecated} <- optional_bool(params, "include_deprecated", false),
         {:ok, statuses} <- optional_statuses(Map.get(params, "statuses")) do
      {:ok,
       %{
         product_name: product_name,
         feature_name: feature_name,
         implementation_name: implementation_name,
         include_refs: include_refs,
         include_dangling_states: include_dangling_states,
         include_deprecated: include_deprecated,
         statuses: statuses
       }}
    end
  end

  defp required_string(params, key) do
    case optional_string(params, key) do
      {:ok, nil} -> {:error, "#{key} is required"}
      other -> other
    end
  end

  defp optional_string(params, key) do
    case Map.get(params, key) do
      nil ->
        {:ok, nil}

      value when is_binary(value) ->
        trimmed = String.trim(value)
        if trimmed == "", do: {:error, "#{key} cannot be blank"}, else: {:ok, trimmed}

      value ->
        {:ok, to_string(value)}
    end
  end

  defp optional_bool(params, key, default) do
    case Map.get(params, key, default) do
      value when is_boolean(value) ->
        {:ok, value}

      value when is_binary(value) ->
        case String.downcase(String.trim(value)) do
          "true" -> {:ok, true}
          "false" -> {:ok, false}
          _ -> {:error, "#{key} must be a boolean"}
        end

      value when is_nil(value) ->
        {:ok, default}

      _ ->
        {:error, "#{key} must be a boolean"}
    end
  end

  defp optional_statuses(nil), do: {:ok, nil}
  defp optional_statuses(status) when is_binary(status), do: normalize_status_list([status])
  defp optional_statuses(statuses) when is_list(statuses), do: normalize_status_list(statuses)
  defp optional_statuses(_), do: {:error, "statuses must be a list"}

  defp normalize_status_list(statuses) do
    normalized =
      Enum.map(statuses, fn
        nil -> nil
        "null" -> nil
        status when is_binary(status) -> String.trim(status)
        status -> to_string(status)
      end)

    # feature-context.REQUEST.7, feature-context.REQUEST.7-1, feature-context.RESPONSE.13, feature-context.RESPONSE.14
    if Enum.all?(normalized, &(&1 in @valid_statuses)) do
      {:ok, normalized}
    else
      {:error, "statuses contains an invalid value"}
    end
  end
end
