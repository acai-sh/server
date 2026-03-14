defmodule AcaiWeb.Api.ApiSpec do
  @moduledoc """
  OpenApiSpex specification for the Acai API v1.

  This module defines the OpenAPI specification for the entire API,
  including info, servers, security schemes, and paths.

  See core.API.1, core.API.1-1
  """

  alias OpenApiSpex.{OpenApi, Info, Server, Components, SecurityScheme, PathItem, Tag}

  @spec spec() :: OpenApi.t()
  def spec do
    endpoint_config = Application.get_env(:acai, AcaiWeb.Endpoint)
    url_config = endpoint_config[:url] || []

    server_url = build_server_url(url_config)

    %OpenApi{
      info: %Info{
        title: "Acai API",
        version: "1.0.0",
        description: "API for managing feature specs, implementations, and states"
      },
      servers: [
        %Server{
          url: server_url,
          description: "API v1"
        }
      ],
      paths: %{
        "/push" => %PathItem{
          post: AcaiWeb.Api.PushController.open_api_operation(:create)
        }
      },
      tags: [
        %Tag{
          name: "Actions",
          description:
            "Push specs, refs, and states from your repo to update feature definitions and implementation tracking"
        }
      ],
      components: %Components{
        schemas: %{},
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
    |> OpenApiSpex.resolve_schema_modules()
  end

  # Builds the server URL from Phoenix endpoint configuration.
  # Falls back to relative URL if config is not available.
  defp build_server_url(url_config) do
    host = Keyword.get(url_config, :host, "localhost")
    scheme = Keyword.get(url_config, :scheme, "http")
    port = Keyword.get(url_config, :port, 4000)
    path = Keyword.get(url_config, :path, "/")

    base_url =
      case {scheme, port} do
        {"https", 443} -> "https://#{host}"
        {"http", 80} -> "http://#{host}"
        _ -> "#{scheme}://#{host}:#{port}"
      end

    # Ensure path starts with / and remove trailing slash
    normalized_path =
      path
      |> String.replace_prefix("", "/")
      |> String.trim_trailing("/")

    "#{base_url}#{normalized_path}/api/v1"
  end
end
