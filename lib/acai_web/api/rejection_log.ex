defmodule AcaiWeb.Api.RejectionLog do
  @moduledoc """
  Structured logging for API security and abuse rejections.

  See core.OPERATIONS.2, core.OPERATIONS.3
  """

  require Logger

  # core.OPERATIONS.2 - Emit security and abuse rejections through the application logger.
  # core.OPERATIONS.3 - Keep logged metadata safe and free of raw secrets or payloads.

  @spec security(Plug.Conn.t(), term(), keyword()) :: :ok
  def security(conn, reason, extra \\ []) do
    log_rejection(conn, :security, reason, extra)
  end

  @spec abuse(Plug.Conn.t(), term(), keyword()) :: :ok
  def abuse(conn, reason, extra \\ []) do
    log_rejection(conn, :abuse, reason, extra)
  end

  # core.OPERATIONS.2
  # core.OPERATIONS.3
  @spec emit(map() | keyword()) :: :ok
  def emit(payload) do
    payload =
      payload
      |> Map.new()
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)
      |> Map.new()

    Logger.warning(fn -> {"api_rejection #{Jason.encode!(payload)}", [api_rejection: true]} end)
    :ok
  end

  # core.OPERATIONS.2
  def filter_api_rejection(%{meta: %{api_rejection: true}}, _config), do: :stop
  def filter_api_rejection(_event, _config), do: :ignore

  @spec token_fingerprint(String.t()) :: String.t()
  def token_fingerprint(raw_token) when is_binary(raw_token) do
    :crypto.hash(:sha256, raw_token)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 12)
  end

  defp log_rejection(conn, category, reason, extra) do
    payload =
      conn
      |> base_metadata()
      |> Map.merge(%{category: category, reason: normalize_reason(reason)})
      |> Map.merge(Map.new(extra))

    emit(payload)
  end

  defp base_metadata(conn) do
    %{
      request_id: request_id(conn),
      endpoint: conn.request_path,
      method: conn.method,
      team_id: conn.assigns[:current_team_id],
      token_id: current_token_id(conn),
      request_size: request_size(conn)
    }
  end

  defp request_id(conn) do
    Map.get(conn, :request_id) || List.first(Plug.Conn.get_req_header(conn, "x-request-id"))
  end

  defp current_token_id(conn) do
    case conn.assigns[:current_token] do
      %{id: id} -> id
      _ -> nil
    end
  end

  defp request_size(conn) do
    case List.first(Plug.Conn.get_req_header(conn, "content-length")) do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {size, ""} -> size
          _ -> nil
        end
    end
  end

  defp normalize_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp normalize_reason(reason), do: to_string(reason)
end
