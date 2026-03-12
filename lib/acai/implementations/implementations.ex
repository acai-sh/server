defmodule Acai.Implementations do
  @moduledoc """
  Context for implementations and tracked branches.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Implementations.{Implementation, TrackedBranch}
  alias Acai.Products.Product
  alias Acai.Specs.FeatureImplState

  # --- Implementations ---

  @doc """
  Lists all implementations for a product.
  """
  def list_implementations(%Product{} = product) do
    Repo.all(from i in Implementation, where: i.product_id == ^product.id)
  end

  @doc """
  Gets an implementation by ID.
  """
  def get_implementation!(id), do: Repo.get!(Implementation, id)

  @doc """
  Creates an implementation for a product.
  """
  def create_implementation(_current_scope, %Product{} = product, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:product_id, product.id)
      |> Map.put(:team_id, product.team_id)

    %Implementation{}
    |> Implementation.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an implementation.
  """
  def update_implementation(%Implementation{} = implementation, attrs) do
    implementation
    |> Implementation.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Returns a changeset for an implementation.
  """
  def change_implementation(%Implementation{} = implementation, attrs \\ %{}) do
    Implementation.changeset(implementation, attrs)
  end

  @doc """
  Builds a URL-safe slug for an implementation.

  Format: {sanitized_name}+{uuid_without_dashes}
  """
  def implementation_slug(%Implementation{} = implementation) do
    "#{sanitize_slug_part(implementation.name)}+#{uuid_without_dashes(implementation.id)}"
  end

  @doc """
  Gets an implementation by parsing the slug pattern: {impl_name}+{uuid_without_dashes}.
  Returns nil if not found or invalid format.
  """
  def get_implementation_by_slug(slug) when is_binary(slug) do
    case Regex.run(~r/\+([0-9a-fA-F]{32})$/, slug, capture: :all_but_first) do
      [uuid_part] ->
        case parse_uuid_without_dashes(uuid_part) do
          {:ok, uuid} -> Repo.get(Implementation, uuid)
          :error -> nil
        end

      _ ->
        nil
    end
  end

  defp parse_uuid_without_dashes(uuid_string) when byte_size(uuid_string) == 32 do
    try do
      formatted_uuid =
        String.slice(uuid_string, 0..7) <>
          "-" <>
          String.slice(uuid_string, 8..11) <>
          "-" <>
          String.slice(uuid_string, 12..15) <>
          "-" <>
          String.slice(uuid_string, 16..19) <>
          "-" <>
          String.slice(uuid_string, 20..31)

      {:ok, formatted_uuid}
    rescue
      _ -> :error
    end
  end

  defp parse_uuid_without_dashes(_), do: :error

  defp sanitize_slug_part(name) do
    name
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
    |> case do
      "" -> "implementation"
      slug -> slug
    end
  end

  defp uuid_without_dashes(id) do
    id
    |> to_string()
    |> String.replace("-", "")
  end

  # --- Counting ---

  @doc """
  Counts active implementations for a product.
  """
  def count_active_implementations(%Product{} = product) do
    Repo.one(
      from i in Implementation,
        where: i.product_id == ^product.id and i.is_active == true,
        select: count()
    )
  end

  @doc """
  Batch counts active implementations for a list of products.
  Returns a map of product_id => count.
  """
  def batch_count_active_implementations_for_products(products) when is_list(products) do
    product_ids = Enum.map(products, & &1.id)

    Repo.all(
      from i in Implementation,
        where: i.product_id in ^product_ids and i.is_active == true,
        group_by: i.product_id,
        select: {i.product_id, count()}
    )
    |> Map.new()
  end

  # --- Tracked Branches ---

  @doc """
  Lists all tracked branches for an implementation.
  """
  def list_tracked_branches(%Implementation{} = implementation) do
    Repo.all(from b in TrackedBranch, where: b.implementation_id == ^implementation.id)
  end

  @doc """
  Gets a tracked branch by ID.
  """
  def get_tracked_branch!(id), do: Repo.get!(TrackedBranch, id)

  @doc """
  Creates a tracked branch for an implementation.
  """
  def create_tracked_branch(%Implementation{} = implementation, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:implementation_id, implementation.id)

    %TrackedBranch{}
    |> TrackedBranch.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns a changeset for a tracked branch.
  """
  def change_tracked_branch(%TrackedBranch{} = tracked_branch, attrs \\ %{}) do
    TrackedBranch.changeset(tracked_branch, attrs)
  end

  @doc """
  Counts tracked branches for an implementation.
  """
  def count_tracked_branches(%Implementation{} = implementation) do
    Repo.one(
      from b in TrackedBranch,
        where: b.implementation_id == ^implementation.id,
        select: count()
    )
  end

  @doc """
  Batch counts tracked branches for a list of implementations.
  Returns a map of implementation_id => count.
  """
  def batch_count_tracked_branches(implementations) when is_list(implementations) do
    impl_ids = Enum.map(implementations, & &1.id)

    Repo.all(
      from b in TrackedBranch,
        where: b.implementation_id in ^impl_ids,
        group_by: b.implementation_id,
        select: {b.implementation_id, count()}
    )
    |> Map.new()
  end

  # --- FeatureImplState Counts ---

  @doc """
  Gets feature_impl_state counts for an implementation.
  Returns %{nil => count, assigned: count, blocked: count, completed: count, accepted: count, rejected: count}
  """
  def get_feature_impl_state_counts(%Implementation{} = implementation) do
    state =
      Repo.one(
        from fis in FeatureImplState,
          where: fis.implementation_id == ^implementation.id,
          select: fis.states
      ) || %{}

    counts = %{
      nil => 0,
      "assigned" => 0,
      "blocked" => 0,
      "completed" => 0,
      "accepted" => 0,
      "rejected" => 0
    }

    Enum.reduce(state, counts, fn {_acid, attrs}, acc ->
      status = attrs["status"]
      Map.update(acc, status, 1, &(&1 + 1))
    end)
  end

  # Deprecated: Use get_feature_impl_state_counts/1 instead
  def get_spec_impl_state_counts(%Implementation{} = implementation) do
    get_feature_impl_state_counts(implementation)
  end

  @doc """
  Batch gets feature_impl_state counts for multiple implementations and optional feature_names.
  Returns a map of implementation_id => %{nil => count, assigned: count, blocked: count, completed: count, accepted: count, rejected: count}

  When feature_names are provided, only counts states for those features. Otherwise counts all states.
  """
  def batch_get_feature_impl_state_counts(implementations, specs \\ nil)
      when is_list(implementations) do
    impl_ids = Enum.map(implementations, & &1.id)
    feature_names = if specs, do: Enum.map(specs, & &1.feature_name) |> Enum.uniq(), else: nil

    states =
      if feature_names do
        Repo.all(
          from fis in FeatureImplState,
            where: fis.implementation_id in ^impl_ids and fis.feature_name in ^feature_names,
            select: {fis.implementation_id, fis.states}
        )
      else
        Repo.all(
          from fis in FeatureImplState,
            where: fis.implementation_id in ^impl_ids,
            select: {fis.implementation_id, fis.states}
        )
      end

    # Aggregate states from multiple feature_names per implementation
    # Each implementation may have multiple rows (one per feature_name), so we merge them
    states_by_impl =
      Enum.reduce(states, %{}, fn {impl_id, feature_states}, acc ->
        Map.update(acc, impl_id, feature_states, &Map.merge(&1, feature_states))
      end)

    impl_ids
    |> Map.new(fn impl_id ->
      state = Map.get(states_by_impl, impl_id, %{})

      counts = %{
        nil => 0,
        "assigned" => 0,
        "blocked" => 0,
        "completed" => 0,
        "accepted" => 0,
        "rejected" => 0
      }

      final_counts =
        Enum.reduce(state, counts, fn {_acid, attrs}, acc ->
          status = attrs["status"]
          Map.update(acc, status, 1, &(&1 + 1))
        end)

      {impl_id, final_counts}
    end)
  end

  # Deprecated: Use batch_get_feature_impl_state_counts/2 instead
  def batch_get_spec_impl_state_counts(implementations, specs \\ nil) do
    batch_get_feature_impl_state_counts(implementations, specs)
  end

  # --- Active Implementations for Specs ---

  @doc """
  Lists all active implementations for a list of specs.
  This finds implementations through the product relationship.
  """
  def list_active_implementations_for_specs(specs) when is_list(specs) do
    product_ids = specs |> Enum.map(& &1.product_id) |> Enum.uniq()

    Repo.all(
      from i in Implementation,
        where: i.product_id in ^product_ids and i.is_active == true
    )
  end
end
