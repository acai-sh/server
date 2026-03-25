defmodule AcaiWeb.Api.RateLimiter do
  @moduledoc """
  Shared in-memory rate limiter for API requests.

  See core.OPERATIONS.1.
  """

  @table :acai_web_api_rate_limiter

  @spec allow?(atom(), term(), map()) ::
          {:ok, non_neg_integer()} | {:error, :rate_limited, pos_integer()}
  def allow?(endpoint, token_id, %{requests: requests, window_seconds: window_seconds})
      when is_integer(requests) and requests > 0 and is_integer(window_seconds) and
             window_seconds > 0 do
    ensure_table!()

    bucket = current_bucket(window_seconds)
    key = {endpoint, token_id || :anonymous, bucket}

    request_count =
      :ets.update_counter(@table, key, {2, 1}, {key, 0})

    if request_count > requests do
      {:error, :rate_limited, request_count}
    else
      {:ok, request_count}
    end
  end

  def allow?(_endpoint, _token_id, _rate_limit), do: {:ok, 0}

  defp current_bucket(window_seconds) do
    System.system_time(:second)
    |> div(window_seconds)
  end

  defp ensure_table! do
    case :ets.whereis(@table) do
      :undefined ->
        try do
          :ets.new(@table, [
            :named_table,
            :public,
            :set,
            read_concurrency: true,
            write_concurrency: true
          ])
        rescue
          ArgumentError -> :ok
        end

      _ ->
        :ok
    end
  end
end
