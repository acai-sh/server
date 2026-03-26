defmodule AcaiWeb.Api.ImplementationFeaturesController do
  @moduledoc """
  Read-only API controller for implementation feature summaries.
  """

  use AcaiWeb.Api.Controller

  alias Acai.Specs
  alias AcaiWeb.Api.Schemas.ReadSchemas

  @valid_statuses [nil, "assigned", "blocked", "incomplete", "completed", "rejected", "accepted"]

  # implementation-features.ENDPOINT.1, implementation-features.ENDPOINT.2
  tags(["Actions"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "List implementation features",
    description: """
    Return a summary list of Features that are visible to a given Implementation.
    These features may be defined in specs that were pushed directly to that Implementation, or inherited from a parent Implementation.
    The response is a summary list of features, containing some metadata and a summary of code references. This is useful to quickly identify features that may have changed or are missing references.
    """,
    parameters: [
      # implementation-features.REQUEST.1
      OpenApiSpex.Operation.parameter(:product_name, :query, :string, "Product name",
        required: true
      ),
      # implementation-features.REQUEST.2
      OpenApiSpex.Operation.parameter(
        :implementation_name,
        :query,
        :string,
        "Implementation name",
        required: true
      ),
      OpenApiSpex.Operation.parameter(
        :statuses,
        :query,
        %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :string}},
        "Repeated status filter values; the literal string `null` means a null status",
        required: false
      ),
      OpenApiSpex.Operation.parameter(
        :changed_since_commit,
        :query,
        :string,
        "Filter by feature's last_seen_commit (simple equality)",
        required: false
      )
    ],
    responses: [
      ok:
        {"Implementation features", "application/json",
         ReadSchemas.ImplementationFeaturesResponse},
      unauthorized: {"Unauthorized", "application/json", ReadSchemas.ErrorResponse},
      forbidden: {"Forbidden", "application/json", ReadSchemas.ErrorResponse},
      not_found: {"Not found", "application/json", ReadSchemas.ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ReadSchemas.ErrorResponse}
    ]
  )

  # implementation-features.RESPONSE.1, implementation-features.RESPONSE.2, implementation-features.RESPONSE.3, implementation-features.RESPONSE.4, implementation-features.RESPONSE.5, implementation-features.RESPONSE.6, implementation-features.RESPONSE.7, implementation-features.RESPONSE.8, implementation-features.RESPONSE.9, implementation-features.RESPONSE.10, implementation-features.RESPONSE.11
  def index(conn, params) do
    token = conn.assigns.current_token
    team = conn.assigns.current_team
    request_params = merged_params(conn, params)

    with :ok <- ensure_scope(token, "impls:read"),
         :ok <- ensure_scope(token, "specs:read"),
         :ok <- ensure_scope(token, "states:read"),
         :ok <- ensure_scope(token, "refs:read"),
         {:ok, parsed} <- parse_params(request_params),
         {:ok, payload} <-
           Specs.load_implementation_features(
             team,
             parsed.product_name,
             parsed.implementation_name,
             statuses: parsed.statuses,
             changed_since_commit: parsed.changed_since_commit
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
    # implementation-features.REQUEST.1, implementation-features.REQUEST.2, implementation-features.REQUEST.3, implementation-features.REQUEST.3-1, implementation-features.REQUEST.4
    with {:ok, product_name} <- required_string(params, "product_name"),
         {:ok, implementation_name} <- required_string(params, "implementation_name"),
         {:ok, statuses} <- optional_statuses(Map.get(params, "statuses")),
         {:ok, changed_since_commit} <- optional_string(params, "changed_since_commit") do
      {:ok,
       %{
         product_name: product_name,
         implementation_name: implementation_name,
         statuses: statuses,
         changed_since_commit: changed_since_commit
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

    # implementation-features.REQUEST.3, implementation-features.REQUEST.3-1
    if Enum.all?(normalized, &(&1 in @valid_statuses)) do
      {:ok, normalized}
    else
      {:error, "statuses contains an invalid value"}
    end
  end
end
