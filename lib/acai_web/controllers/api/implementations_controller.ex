defmodule AcaiWeb.Api.ImplementationsController do
  @moduledoc """
  Read-only API controller for implementation discovery.
  """

  use AcaiWeb.Api.Controller

  alias Acai.Products
  alias Acai.Implementations
  alias AcaiWeb.Api.Schemas.ReadSchemas

  # implementations.ENDPOINT.1, implementations.ENDPOINT.2
  tags(["Actions"])
  security([%{"bearerAuth" => []}])

  operation(:index,
    summary: "List implementations",
    description:
      "Discover which implementations exist for a product and which of them are relevant to a repo branch or feature. This is the orientation endpoint: agents call it when they know their current repo and branch but do not yet know which implementation they should read from or write to. Filtering by feature returns only implementations that can resolve that feature through their tracked branches or parent inheritance.",
    parameters: [
      # implementations.REQUEST.1
      OpenApiSpex.Operation.parameter(:product_name, :query, :string, "Product name",
        required: true
      ),
      OpenApiSpex.Operation.parameter(:repo_uri, :query, :string, "Exact repository URI",
        required: false
      ),
      OpenApiSpex.Operation.parameter(:branch_name, :query, :string, "Exact branch name",
        required: false
      ),
      OpenApiSpex.Operation.parameter(
        :feature_name,
        :query,
        :string,
        "Filter to implementations that can resolve this feature",
        required: false
      )
    ],
    responses: [
      ok: {"Implementation list", "application/json", ReadSchemas.ImplementationsResponse},
      unauthorized: {"Unauthorized", "application/json", ReadSchemas.ErrorResponse},
      forbidden: {"Forbidden", "application/json", ReadSchemas.ErrorResponse},
      unprocessable_entity: {"Validation error", "application/json", ReadSchemas.ErrorResponse}
    ]
  )

  # implementations.RESPONSE.1, implementations.RESPONSE.8, implementations.RESPONSE.9, implementations.RESPONSE.10
  def index(conn, params) do
    token = conn.assigns.current_token
    team = conn.assigns.current_team
    request_params = merged_params(conn, params)

    with :ok <- ensure_scope(token, "impls:read"),
         {:ok, parsed} <- parse_params(request_params),
         :ok <- ensure_feature_scope(token, parsed.feature_name),
         {:ok, payload} <- build_payload(team, parsed) do
      render_data(conn, payload)
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_payload(team, %{
         product_name: product_name,
         repo_uri: repo_uri,
         branch_name: branch_name,
         feature_name: feature_name
       }) do
    # implementations.FILTERS.1, implementations.FILTERS.2, implementations.FILTERS.5, implementations.RESPONSE.2, implementations.RESPONSE.3, implementations.RESPONSE.4, implementations.RESPONSE.5
    branch_filter = if repo_uri && branch_name, do: {repo_uri, branch_name}, else: nil

    implementations =
      case Products.get_product_by_team_and_name(team, product_name) do
        {:ok, product} ->
          Implementations.list_api_implementations(team, product,
            branch_filter: branch_filter,
            feature_name: feature_name
          )

        {:error, :not_found} ->
          []
      end

    data =
      %{
        product_name: product_name,
        implementations:
          Enum.map(implementations, fn implementation ->
            %{implementation_name: implementation.name, implementation_id: implementation.id}
          end)
      }
      |> maybe_put_branch_filter(repo_uri, branch_name)

    {:ok, data}
  end

  defp maybe_put_branch_filter(data, nil, nil), do: data

  defp maybe_put_branch_filter(data, repo_uri, branch_name),
    do: Map.merge(data, %{repo_uri: repo_uri, branch_name: branch_name})

  defp merged_params(conn, params) do
    conn.query_params
    |> Map.merge(conn.body_params || %{})
    |> Map.merge(params || %{})
  end

  defp ensure_feature_scope(_token, nil), do: :ok

  defp ensure_feature_scope(token, _feature_name) when is_map(token) do
    # implementations.ENDPOINT.2, implementations.FILTERS.6
    if Acai.Teams.token_has_scope?(token, "specs:read"),
      do: :ok,
      else: {:error, {:forbidden, "Token missing required scope: specs:read"}}
  end

  defp ensure_scope(token, scope) do
    if Acai.Teams.token_has_scope?(token, scope),
      do: :ok,
      else: {:error, {:forbidden, "Token missing required scope: #{scope}"}}
  end

  defp parse_params(params) do
    # implementations.REQUEST.1, implementations.REQUEST.2, implementations.REQUEST.3, implementations.REQUEST.4, implementations.FILTERS.3, implementations.FILTERS.4, implementations.RESPONSE.8
    with {:ok, product_name} <- required_string(params, "product_name"),
         {:ok, repo_uri} <- optional_string(params, "repo_uri"),
         {:ok, branch_name} <- optional_string(params, "branch_name"),
         {:ok, feature_name} <- optional_string(params, "feature_name"),
         :ok <- validate_branch_pair(repo_uri, branch_name) do
      {:ok,
       %{
         product_name: product_name,
         repo_uri: repo_uri,
         branch_name: branch_name,
         feature_name: feature_name
       }}
    end
  end

  defp validate_branch_pair(nil, nil), do: :ok

  defp validate_branch_pair(_repo_uri, nil),
    do: {:error, "branch_name is required when repo_uri is provided"}

  defp validate_branch_pair(nil, _branch_name),
    do: {:error, "repo_uri is required when branch_name is provided"}

  defp validate_branch_pair(_repo_uri, _branch_name), do: :ok

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
end
