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
end
