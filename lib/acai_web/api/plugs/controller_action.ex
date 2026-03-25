defmodule AcaiWeb.Api.Plugs.ControllerAction do
  @moduledoc """
  Seeds Phoenix controller/action metadata for router-level OpenAPI validation.

  See core.ENG.1
  """

  import Plug.Conn

  alias AcaiWeb.Api.Operations

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    case Operations.endpoint_key(conn) do
      :push ->
        conn
        |> put_private(:phoenix_controller, AcaiWeb.Api.PushController)
        |> put_private(:phoenix_action, :create)

      _other ->
        conn
    end
  end
end
