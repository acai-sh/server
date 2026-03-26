defmodule AcaiWeb.Api.PushController do
  @moduledoc """
  Controller for the push endpoint.

  Handles POST /api/v1/push for pushing specs and refs.
  """

  use AcaiWeb.Api.Controller

  alias Acai.Services.Push
  alias AcaiWeb.Api.Schemas.PushSchemas

  # core.ENG.3 - Define OpenAPI route documentation inline using the controller operation macro.
  tags(["Actions"])
  security([%{"bearerAuth" => []}])

  operation(:create,
    summary: "Push from branch",
    description: """
    Sync data from your current git branch to the server.
    - Upload specs (feature.yaml files) and the requirements and metadata defined in them.
    - Upload code references (ACID tags) found in source code, and their file paths.

    This endpoint can create or link implementations while syncing specs and refs, but it does not
    accept feature-state writes or configure implementation settings directly.

    Use this when source code or specs have changed on a branch.
    This endpoint is primarily intended to serve the `acai push` CLI command.
    """,
    # push.REQUEST.9, push.REQUEST.10, push.RESPONSE.8, push.RESPONSE.9
    request_body: {"Push request body", "application/json", PushSchemas.PushRequest},
    responses: [
      ok: {"Push successful", "application/json", PushSchemas.PushResponse},
      unauthorized:
        {"Unauthorized - invalid or missing token", "application/json", PushSchemas.ErrorResponse},
      forbidden:
        {"Forbidden - token missing required scopes", "application/json",
         PushSchemas.ErrorResponse},
      request_entity_too_large:
        {"Payload too large", "application/json", PushSchemas.ErrorResponse},
      too_many_requests: {"Rate limit exceeded", "application/json", PushSchemas.ErrorResponse},
      unprocessable_entity:
        {"Validation error - invalid request body", "application/json", PushSchemas.ErrorResponse}
    ]
  )

  @doc """
  Handles the push request.

  See push.ENDPOINT.1, push.ENDPOINT.2, push.ENDPOINT.3
  See push.REQUEST.1 through push.REQUEST.5, push.REQUEST.7 through push.REQUEST.10
  See push.RESPONSE.1 through push.RESPONSE.9
  """
  def create(conn, _params) do
    token = conn.assigns.current_token
    params = conn.body_params || %{}

    with {:ok, response_data} <- Push.execute(token, params) do
      # push.RESPONSE.1 - Return data wrapped in success response
      render_data(conn, response_data)
    end
  end
end
