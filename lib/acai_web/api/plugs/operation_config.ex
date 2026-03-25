defmodule AcaiWeb.Api.Plugs.OperationConfig do
  @moduledoc """
  Loads runtime API operation config and enforces shared request-size caps and rate limits.

  See core.OPERATIONS.1, core.OPERATIONS.2, core.OPERATIONS.3
  """

  import Plug.Conn

  alias AcaiWeb.Api.{FallbackController, Operations, RateLimiter, RejectionLog}

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    endpoint = Operations.endpoint_key(conn)
    config = Operations.config(endpoint)

    conn = put_private(conn, :api_operation_config, config)

    case oversized_request?(conn, config) do
      {true, request_size, cap} ->
        RejectionLog.abuse(conn, :payload_too_large,
          endpoint: conn.request_path,
          request_size: request_size,
          request_size_cap: cap
        )

        conn
        |> FallbackController.call({:error, :payload_too_large})
        |> halt()

      false ->
        case rate_limited?(conn, endpoint, config) do
          {true, request_count, rate_limit} ->
            RejectionLog.abuse(conn, :rate_limited,
              endpoint: conn.request_path,
              request_count: request_count,
              request_limit: rate_limit[:requests],
              window_seconds: rate_limit[:window_seconds]
            )

            conn
            |> FallbackController.call({:error, :rate_limited})
            |> halt()

          false ->
            conn
        end
    end
  end

  defp oversized_request?(conn, config) do
    with cap when is_integer(cap) <- config[:request_size_cap],
         request_size when is_integer(request_size) <- content_length(conn),
         true <- request_size > cap do
      {true, request_size, cap}
    else
      _ -> false
    end
  end

  defp content_length(conn) do
    case List.first(get_req_header(conn, "content-length")) do
      nil ->
        nil

      value ->
        case Integer.parse(value) do
          {request_size, ""} -> request_size
          _ -> nil
        end
    end
  end

  defp rate_limited?(conn, endpoint, config) do
    case config[:rate_limit] do
      %{requests: requests, window_seconds: window_seconds} = rate_limit
      when is_integer(requests) and requests > 0 and is_integer(window_seconds) and
             window_seconds > 0 ->
        case RateLimiter.allow?(endpoint, conn.assigns[:current_token_id], rate_limit) do
          {:ok, _request_count} -> false
          {:error, :rate_limited, request_count} -> {true, request_count, rate_limit}
        end

      _ ->
        false
    end
  end
end
