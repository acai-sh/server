defmodule AcaiWeb.Api.OperationsTest do
  @moduledoc """
  Tests for shared API operation configuration.

  ACIDs:
  - core.OPERATIONS.1 - Runtime-configurable operation limits and rate settings
  """

  use ExUnit.Case, async: false

  alias AcaiWeb.Api.Operations

  setup do
    original = Application.get_env(:acai, :api_operations)

    on_exit(fn ->
      if is_nil(original) do
        Application.delete_env(:acai, :api_operations)
      else
        Application.put_env(:acai, :api_operations, original)
      end
    end)

    :ok
  end

  test "merges endpoint config over runtime defaults" do
    Application.put_env(:acai, :api_operations, %{
      default: %{
        request_size_cap: 10,
        semantic_caps: %{max_specs: 1, max_references: 2},
        rate_limit: %{window_seconds: 60, requests: 3}
      },
      push: %{
        semantic_caps: %{max_specs: 9}
      }
    })

    assert Operations.request_size_cap(:push) == 10
    assert Operations.semantic_caps(:push) == %{max_specs: 9, max_references: 2}
    assert Operations.rate_limit(:push) == %{window_seconds: 60, requests: 3}
  end

  test "uses the feature-states default ACID cap from runtime config" do
    caps = Operations.semantic_caps(:feature_states)

    assert caps[:max_states] == 500
    assert caps[:max_comment_length] == 2_000
  end

  test "resolves endpoint keys from API paths" do
    push_conn = %Plug.Conn{request_path: "/api/v1/push"}
    feature_states_conn = %Plug.Conn{request_path: "/api/v1/feature-states"}

    assert Operations.endpoint_key(push_conn) == :push
    assert Operations.endpoint_key(feature_states_conn) == :feature_states
  end
end
