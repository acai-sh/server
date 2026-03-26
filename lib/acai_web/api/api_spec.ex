defmodule AcaiWeb.Api.ApiSpec do
  @moduledoc """
  OpenApiSpex specification for the Acai API v1.

  This module defines the OpenAPI specification for the entire API,
  including info, servers, security schemes, and paths.

  See core.API.1, core.API.1-1
  """

  alias OpenApiSpex.{OpenApi, Info, Server, Components, SecurityScheme, Tag}

  @spec spec() :: OpenApi.t()
  def spec do
    endpoint_config = Application.get_env(:acai, AcaiWeb.Endpoint)
    url_config = endpoint_config[:url] || []

    server_url = build_server_url(url_config)

    %OpenApi{
      info: %Info{
        title: "Acai API",
        version: "1.0.0",
        # push.ABUSE.2-1, push.ABUSE.4
        description:
          "Acai is an API for spec-driven development across git branches and product implementations. Specs store canonical requirement definitions, refs store where code on a branch appears to implement those requirements, and states store implementation-specific progress such as completed, blocked, or accepted. Agents typically discover an implementation, read canonical feature context, sync branch-derived changes, and then record status updates separately."
      },
      servers: [
        %Server{
          url: server_url,
          description: "API v1"
        }
      ],
      paths: build_paths(),
      tags: [
        %Tag{
          name: "Actions",
          # push.ABUSE.2-1, push.ABUSE.4
          description:
            "Endpoints for syncing branch-derived truth, resolving canonical feature context, discovering implementation work, and recording implementation-specific progress. The API keeps specs and refs separate from status updates so agents can read shared requirements, push observed code changes, and write progress without mixing those concerns."
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

  defp build_paths do
    AcaiWeb.Router
    |> OpenApiSpex.Paths.from_router()
    |> Map.new(fn {path, path_item} ->
      {String.replace_prefix(path, "/api/v1", ""), path_item}
    end)
  end
end
