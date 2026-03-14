defmodule AcaiWeb.Api.ErrorJSON do
  @moduledoc """
  JSON error rendering for API responses.

  See core.ENG.4, core.ENG.5
  """

  @doc """
  Renders an error response with the standard error format.
  """
  def render("error.json", %{status: status, detail: detail}) do
    %{
      errors: %{
        detail: detail,
        status: status_to_string(status)
      }
    }
  end

  # Fallback for generic templates renders the status message.
  def render(template, _assigns) do
    %{errors: %{detail: Phoenix.Controller.status_message_from_template(template)}}
  end

  defp status_to_string(status) when is_atom(status) do
    status |> to_string() |> String.upcase()
  end

  defp status_to_string(status) when is_integer(status) do
    status |> Plug.Conn.Status.reason_atom() |> status_to_string()
  end

  defp status_to_string(status), do: to_string(status)
end
