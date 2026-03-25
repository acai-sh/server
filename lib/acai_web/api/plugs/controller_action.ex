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

      :implementations ->
        conn
        |> put_private(:phoenix_controller, AcaiWeb.Api.ImplementationsController)
        |> put_private(:phoenix_action, :index)

      :feature_context ->
        conn
        |> put_private(:phoenix_controller, AcaiWeb.Api.FeatureContextController)
        |> put_private(:phoenix_action, :show)

      :implementation_features ->
        conn
        |> put_private(:phoenix_controller, AcaiWeb.Api.ImplementationFeaturesController)
        |> put_private(:phoenix_action, :index)

      :feature_states ->
        conn
        |> put_private(:phoenix_controller, AcaiWeb.Api.FeatureStatesController)
        |> put_private(:phoenix_action, :update)

      _other ->
        conn
    end
  end
end
