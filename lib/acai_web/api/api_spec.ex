defmodule AcaiWeb.Api.ApiSpec do
  @moduledoc """
  OpenApiSpex specification for the Acai API v1.

  This module defines the OpenAPI specification for the entire API,
  including info, servers, security schemes, and paths.

  See core.API.1, core.API.1-1
  """

  alias OpenApiSpex.{OpenApi, Info, Server, Components, SecurityScheme}
  alias AcaiWeb.Api.Schemas.PushSchemas

  @spec spec() :: OpenApi.t()
  def spec do
    %OpenApi{
      info: %Info{
        title: "Acai API",
        version: "1.0.0",
        description: "API for managing feature specs, implementations, and states"
      },
      servers: [
        %Server{
          url: "/api/v1",
          description: "API v1"
        }
      ],
      paths: %{
        "/push" => %{
          "post" => AcaiWeb.Api.PushController.open_api_operation(:create)
        }
      },
      components: %Components{
        schemas: %{
          "Feature" => PushSchemas.Feature,
          "FeatureMeta" => PushSchemas.FeatureMeta,
          "RequirementDefinition" => PushSchemas.RequirementDefinition,
          "Requirements" => PushSchemas.Requirements,
          "SpecObject" => PushSchemas.SpecObject,
          "RefObject" => PushSchemas.RefObject,
          "References" => PushSchemas.References,
          "StateObject" => PushSchemas.StateObject,
          "States" => PushSchemas.States,
          "PushRequest" => PushSchemas.PushRequest,
          "PushResponseData" => PushSchemas.PushResponseData,
          "PushResponse" => PushSchemas.PushResponse,
          "ErrorResponse" => PushSchemas.ErrorResponse
        },
        securitySchemes: %{
          "bearerAuth" => %SecurityScheme{
            type: "http",
            scheme: "bearer",
            bearerFormat: "API token"
          }
        }
      },
      security: [%{"bearerAuth" => []}]
    }
  end
end
