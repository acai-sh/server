defmodule AcaiWeb.Api.Controller do
  @moduledoc """
  Base controller for API controllers.

  Provides common functionality for all API controllers including:
  - action_fallback for consistent error handling (core.ENG.5)
  - Data wrapping for successful responses (core.ENG.4)
  - OpenApiSpex operation macro support (core.ENG.3)

  See core.ENG.3, core.ENG.4, core.ENG.5
  """

  defmacro __using__(_opts) do
    quote do
      use AcaiWeb, :controller
      use OpenApiSpex.ControllerSpecs

      # core.ENG.5 - Use action_fallback for unified error handling
      action_fallback AcaiWeb.Api.FallbackController

      @doc """
      Renders a successful response wrapped in a data key.

      See core.ENG.4
      """
      def render_data(conn, data) do
        json(conn, %{data: data})
      end
    end
  end
end
