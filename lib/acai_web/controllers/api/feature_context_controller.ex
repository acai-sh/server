defmodule AcaiWeb.Api.FeatureContextController do
  @moduledoc """
  Read-only API controller for canonical feature context.
  """

  use AcaiWeb.Api.Controller

  alias Acai.Specs
  alias AcaiWeb.Api.Schemas.ReadSchemas

  # feature-context.ENDPOINT.1, feature-context.ENDPOINT.2
  tags(["Actions"])
  security([%{"bearerAuth" => []}])

  operation(:show,
    summary: "Read canonical feature context",
    description:
      "Return the canonical context for one feature in one implementation. This is the main read endpoint for spec-driven work: it resolves the requirement definitions the implementation should follow and optional code refs that point to matching files on tracked branches. Agents should call this before making code changes so they work from the same inherited source of truth that reviewers and dashboards use.",
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
        :include_deprecated,
        :query,
        :boolean,
        "Include deprecated ACIDs",
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
         :ok <- ensure_scope(token, "refs:read"),
         {:ok, parsed} <- parse_params(request_params),
         {:ok, payload} <-
           Specs.get_feature_context(
             team,
             parsed.product_name,
             parsed.feature_name,
             parsed.implementation_name,
             include_refs: parsed.include_refs,
             include_deprecated: parsed.include_deprecated
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
         {:ok, include_deprecated} <- optional_bool(params, "include_deprecated", false) do
      {:ok,
       %{
         product_name: product_name,
         feature_name: feature_name,
         implementation_name: implementation_name,
         include_refs: include_refs,
         include_deprecated: include_deprecated
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
end
