defmodule AcaiWeb.Api.OpenApiController do
  @moduledoc """
  Controller for serving the OpenAPI specification.

  See core.API.1, core.API.1-1
  """

  use AcaiWeb, :controller

  alias OpenApiSpex.OpenApi

  @doc """
  Renders the OpenAPI JSON specification.
  """
  def spec(conn, _params) do
    # Get the spec module from the connection (set by PutApiSpec plug)
    spec_module = conn.private.open_api_spex.spec_module

    # Call the spec function to get the actual spec
    spec = spec_module.spec()

    # Render the spec as JSON
    conn
    |> put_resp_content_type("application/json")
    |> send_resp(200, Jason.encode!(OpenApi.to_map(spec)))
  end
end
