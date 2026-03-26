defmodule AcaiWeb.Api.Operations do
  @moduledoc """
  Shared runtime configuration for API operations.

  See core.OPERATIONS.1
  """

  # core.OPERATIONS.1 - Keep request-size caps, semantic caps, and rate-limit settings runtime-configurable.

  @default_endpoint :default

  @spec config(atom() | String.t()) :: map()
  def config(endpoint) do
    operations = Application.get_env(:acai, :api_operations, %{}) |> Map.new()

    default_config = Map.get(operations, @default_endpoint, %{})
    endpoint_config = Map.get(operations, normalize_endpoint(endpoint), %{})

    deep_merge(default_config, endpoint_config)
  end

  @spec request_size_cap(atom() | String.t()) :: non_neg_integer() | nil
  def request_size_cap(endpoint), do: config(endpoint)[:request_size_cap]

  @spec semantic_caps(atom() | String.t()) :: map()
  def semantic_caps(endpoint), do: config(endpoint)[:semantic_caps] || %{}

  @spec rate_limit(atom() | String.t()) :: map()
  def rate_limit(endpoint), do: config(endpoint)[:rate_limit] || %{}

  @spec endpoint_key(Plug.Conn.t()) :: atom()
  def endpoint_key(%Plug.Conn{request_path: "/api/v1/push"}), do: :push
  def endpoint_key(%Plug.Conn{request_path: "/api/v1/implementations"}), do: :implementations
  def endpoint_key(%Plug.Conn{request_path: "/api/v1/feature-context"}), do: :feature_context

  def endpoint_key(%Plug.Conn{request_path: "/api/v1/implementation-features"}),
    do: :implementation_features

  def endpoint_key(%Plug.Conn{request_path: "/api/v1/feature-states"}), do: :feature_states
  def endpoint_key(_conn), do: @default_endpoint

  defp normalize_endpoint(endpoint) when is_atom(endpoint), do: endpoint

  defp normalize_endpoint(endpoint) when is_binary(endpoint) do
    case endpoint do
      "push" -> :push
      "implementations" -> :implementations
      "feature-context" -> :feature_context
      "implementation-features" -> :implementation_features
      "feature-states" -> :feature_states
      "default" -> @default_endpoint
      _other -> @default_endpoint
    end
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value ->
      deep_merge(left_value, right_value)
    end)
  end

  defp deep_merge(_left, right), do: right
end
