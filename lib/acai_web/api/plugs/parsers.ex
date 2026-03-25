defmodule AcaiWeb.Api.Plugs.Parsers do
  @moduledoc """
  Wraps Plug.Parsers with runtime body-size caps for API requests.

  See core.OPERATIONS.1
  """

  alias AcaiWeb.Api.Operations
  alias AcaiWeb.Api.{FallbackController, RejectionLog}

  import Plug.Conn

  @default_body_length 8_000_000

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, opts) do
    if api_request?(conn) do
      endpoint = Operations.endpoint_key(conn)
      request_size_cap = Operations.request_size_cap(endpoint) || @default_body_length
      opts = Keyword.put_new(opts, :length, request_size_cap)

      case content_length(conn) do
        size when is_integer(size) and size > request_size_cap ->
          # core.OPERATIONS.1
          reject_too_large(conn, size, request_size_cap)

        _ ->
          try do
            Plug.Parsers.call(conn, Plug.Parsers.init(opts))
          rescue
            Plug.Parsers.RequestTooLargeError ->
              # core.OPERATIONS.1
              reject_too_large(conn, request_size_cap + 1, request_size_cap)
          end
      end
    else
      Plug.Parsers.call(conn, Plug.Parsers.init(opts))
    end
  end

  defp api_request?(%Plug.Conn{request_path: path}) do
    path == "/api/v1" or String.starts_with?(path, "/api/v1/")
  end

  defp content_length(conn) do
    conn
    |> get_req_header("content-length")
    |> List.first()
    |> case do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {size, ""} -> size
          _ -> nil
        end
    end
  end

  defp reject_too_large(conn, request_size, request_size_cap) do
    RejectionLog.abuse(conn, :payload_too_large,
      endpoint: conn.request_path,
      request_size: request_size,
      request_size_cap: request_size_cap
    )

    conn
    |> FallbackController.call({:error, :payload_too_large})
    |> halt()
  end
end
