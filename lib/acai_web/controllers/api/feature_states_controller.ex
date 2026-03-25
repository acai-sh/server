defmodule AcaiWeb.Api.FeatureStatesController do
  @moduledoc """
  Controller for the feature-states endpoint.
  """

  use AcaiWeb.Api.Controller

  alias Acai.Services.FeatureStates
  alias AcaiWeb.Api.RejectionLog
  alias AcaiWeb.Api.Schemas.{FeatureStatesSchemas, ReadSchemas}

  # feature-states.ENDPOINT.1, feature-states.ENDPOINT.2, feature-states.ENDPOINT.3
  tags(["Actions"])
  security([%{"bearerAuth" => []}])

  operation(:update,
    summary: "Write feature states",
    description:
      "Record implementation-specific progress for one feature in one implementation. State writes do not change requirement text or code refs; they only capture how this implementation currently evaluates each requirement, for example assigned, blocked, completed, or accepted. On first write, local state starts from the parent implementation when one exists, then applies the incoming changes. Use this after analysis, coding, review, or QA to record progress without changing branch-derived truth.",
    request_body:
      {"Feature states request body", "application/json",
       FeatureStatesSchemas.FeatureStatesRequest},
    responses: [
      ok:
        {"Feature states written", "application/json", FeatureStatesSchemas.FeatureStatesResponse},
      unauthorized: {"Unauthorized", "application/json", ReadSchemas.ErrorResponse},
      forbidden: {"Forbidden", "application/json", ReadSchemas.ErrorResponse},
      not_found: {"Not found", "application/json", ReadSchemas.ErrorResponse},
      request_entity_too_large:
        {"Payload too large", "application/json", ReadSchemas.ErrorResponse},
      too_many_requests: {"Rate limit exceeded", "application/json", ReadSchemas.ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ReadSchemas.ErrorResponse}
    ]
  )

  # feature-states.RESPONSE.1 through feature-states.RESPONSE.10
  def update(conn, params) do
    token = conn.assigns.current_token
    team = conn.assigns.current_team
    request_params = merged_params(conn, params)

    with :ok <- ensure_scope(token, "impls:read"),
         :ok <- ensure_scope(token, "specs:read"),
         :ok <- ensure_scope(token, "states:write"),
         {:ok, payload} <- FeatureStates.execute(team, request_params) do
      render_data(conn, payload)
    else
      {:error, :not_found} ->
        {:error, :not_found}

      {:error, {:forbidden, reason}} ->
        {:error, {:forbidden, reason}}

      {:error, {reason, meta}} ->
        validation_error(conn, request_params, reason, meta)

      {:error, reason} when is_binary(reason) ->
        validation_error(conn, request_params, reason, %{})
    end
  end

  defp validation_error(conn, request_params, reason, meta) do
    # feature-states.ABUSE.5-1, feature-states.ABUSE.5-2, feature-states.ABUSE.5-3
    meta = if is_map(meta), do: meta, else: %{}

    RejectionLog.abuse(
      conn,
      :validation_error,
      Keyword.merge(
        [summary: safe_summary(request_params), validation_reason: reason],
        Map.to_list(meta)
      )
    )

    {:error, reason}
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

  defp safe_summary(params) do
    %{
      product_name: Map.get(params, "product_name") || Map.get(params, :product_name),
      feature_name: Map.get(params, "feature_name") || Map.get(params, :feature_name),
      implementation_name:
        Map.get(params, "implementation_name") || Map.get(params, :implementation_name),
      states_count: state_count(params)
    }
  end

  defp state_count(params) do
    case Map.get(params, "states") || Map.get(params, :states) do
      states when is_map(states) -> map_size(states)
      _ -> 0
    end
  end
end
