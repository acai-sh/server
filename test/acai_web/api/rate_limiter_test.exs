defmodule AcaiWeb.Api.RateLimiterTest do
  @moduledoc """
  Tests for the shared API rate limiter.

  ACIDs:
  - core.OPERATIONS.1 - API abuse protections and limits are enforced at runtime
  """

  use ExUnit.Case, async: false

  alias AcaiWeb.Api.RateLimiter

  test "limits requests per token within a window" do
    rate_limit = %{requests: 1, window_seconds: 60}
    token_id = System.unique_integer([:positive])

    assert {:ok, 1} = RateLimiter.allow?(:push, token_id, rate_limit)
    assert {:error, :rate_limited, 2} = RateLimiter.allow?(:push, token_id, rate_limit)
    assert {:ok, 1} = RateLimiter.allow?(:push, token_id + 1, rate_limit)
  end

  test "prunes expired rate limit buckets" do
    rate_limit = %{requests: 1, window_seconds: 60}
    token_id = System.unique_integer([:positive])
    now = System.system_time(:second)
    current_bucket = div(now, rate_limit.window_seconds)
    expired_key = {:push, token_id, current_bucket - 1}

    case :ets.whereis(:acai_web_api_rate_limiter) do
      :undefined -> :ok
      tid -> :ets.delete(tid)
    end

    :ets.new(:acai_web_api_rate_limiter, [:named_table, :public, :set])
    :ets.insert(:acai_web_api_rate_limiter, {expired_key, 1, now - 1})

    assert {:ok, 1} = RateLimiter.allow?(:push, token_id, rate_limit)
    assert [] == :ets.lookup(:acai_web_api_rate_limiter, expired_key)
  end
end
