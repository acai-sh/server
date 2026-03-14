defmodule AcaiWeb.Api.PushController do
  @moduledoc """
  Controller for the push endpoint.

  Handles POST /api/v1/push for pushing specs, refs, and states.

  See push.feature.yaml for all ACIDs
  """

  use AcaiWeb.Api.Controller

  alias Acai.Services.Push
  alias AcaiWeb.Api.Schemas.PushSchemas

  @doc """
  OpenAPI operation specification for the push endpoint.

  See push.ENDPOINT.1, push.ENDPOINT.2, push.ENDPOINT.3
  """
  def open_api_operation(:create) do
    alias OpenApiSpex.Operation

    %Operation{
      tags: ["Push"],
      summary: "Push specs, refs, and states",
      description: """
      Push specs, code references, and implementation states to the server.

      This endpoint handles:
      - Creating/updating specs on a branch
      - Creating code references for ACIDs
      - Setting implementation states
      - Auto-creating implementations for new branches
      - Linking branches to existing implementations

      See push.feature.yaml for all ACIDs.
      """,
      operationId: "PushController.create",
      requestBody: %OpenApiSpex.RequestBody{
        description: "Push request body",
        content: %{
          "application/json" => %{
            schema: PushSchemas.PushRequest
          }
        },
        required: true
      },
      responses: %{
        200 => %OpenApiSpex.Response{
          description: "Push successful",
          content: %{
            "application/json" => %{
              schema: PushSchemas.PushResponse
            }
          }
        },
        401 => %OpenApiSpex.Response{
          description: "Unauthorized - invalid or missing token",
          content: %{
            "application/json" => %{
              schema: PushSchemas.ErrorResponse
            }
          }
        },
        403 => %OpenApiSpex.Response{
          description: "Forbidden - token missing required scopes",
          content: %{
            "application/json" => %{
              schema: PushSchemas.ErrorResponse
            }
          }
        },
        422 => %OpenApiSpex.Response{
          description: "Validation error - invalid request body",
          content: %{
            "application/json" => %{
              schema: PushSchemas.ErrorResponse
            }
          }
        }
      },
      security: [%{"bearerAuth" => []}]
    }
  end

  @doc """
  Handles the push request.

  See push.ENDPOINT.1, push.ENDPOINT.2, push.ENDPOINT.3
  See push.REQUEST.1 through push.REQUEST.8
  See push.RESPONSE.1 through push.RESPONSE.7
  """
  def create(conn, params) do
    token = conn.assigns.current_token

    # Validate required fields manually
    with :ok <- validate_required_fields(params) do
      case Push.execute(token, params) do
        {:ok, response_data} ->
          # push.RESPONSE.1 - Return data wrapped in success response
          render_data(conn, response_data)

        {:error, reason} when is_binary(reason) ->
          # Check if it's an auth/scope error or validation error
          cond do
            String.contains?(reason, "scope") ->
              # push.RESPONSE.7 - Scope error returns 403
              conn
              |> put_status(:forbidden)
              |> put_view(json: AcaiWeb.Api.ErrorJSON)
              |> render(:error, status: :forbidden, detail: reason)

            true ->
              # push.RESPONSE.5 - Validation error returns 422
              conn
              |> put_status(:unprocessable_entity)
              |> put_view(json: AcaiWeb.Api.ErrorJSON)
              |> render(:error, status: :unprocessable_entity, detail: reason)
          end

        {:error, %Ecto.Changeset{} = changeset} ->
          # push.RESPONSE.5 - Changeset validation error
          conn
          |> put_status(:unprocessable_entity)
          |> put_view(json: AcaiWeb.Api.ErrorJSON)
          |> render(:error, changeset)
      end
    else
      {:error, reason} ->
        conn
        |> put_status(:unprocessable_entity)
        |> put_view(json: AcaiWeb.Api.ErrorJSON)
        |> render(:error, status: :unprocessable_entity, detail: reason)
    end
  end

  defp validate_required_fields(params) do
    required = [:repo_uri, :branch_name, :commit_hash]

    missing =
      Enum.filter(required, fn field ->
        value = params[field] || params[to_string(field)]
        is_nil(value) || value == ""
      end)

    if missing == [] do
      :ok
    else
      missing_str = Enum.map_join(missing, ", ", &to_string/1)
      {:error, "Missing required fields: #{missing_str}"}
    end
  end
end
