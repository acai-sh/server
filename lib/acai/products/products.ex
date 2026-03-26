defmodule Acai.Products do
  @moduledoc """
  Context for products.
  """

  import Ecto.Query
  alias Acai.Repo
  alias Acai.Products.Product
  alias Acai.Teams.Team

  # data-model.PRODUCTS.1
  # data-model.PRODUCTS.2
  # data-model.PRODUCTS.3
  # data-model.PRODUCTS.4
  # data-model.PRODUCTS.5
  # data-model.PRODUCTS.6

  @doc """
  Lists all products for a team.
  """
  def list_products(_current_scope, %Team{} = team) do
    Repo.all(from p in Product, where: p.team_id == ^team.id)
  end

  @doc """
  Gets a product by ID.
  """
  def get_product!(id), do: Repo.get!(Product, id)

  @doc """
  Gets a product by team and name (case-insensitive via CITEXT).
  """
  def get_product_by_name!(%Team{} = team, name) do
    Repo.get_by!(Product, team_id: team.id, name: name)
  end

  @doc """
  Creates a product for a team.
  """
  def create_product(_current_scope, %Team{} = team, attrs) do
    attrs =
      attrs
      |> Map.new()
      |> Map.put(:team_id, team.id)

    %Product{}
    |> Product.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a product.
  """
  def update_product(%Product{} = product, attrs) do
    product
    |> Product.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a product.
  """
  def delete_product(%Product{} = product) do
    Repo.delete(product)
  end

  @doc """
  Returns a changeset for a product.
  """
  def change_product(%Product{} = product, attrs \\ %{}) do
    Product.changeset(product, attrs)
  end

  @doc """
  Gets a team by name, returns {:ok, team} or {:error, :not_found}.

  Non-raising version of Teams.get_team_by_name!/1 for safe lookups in LiveViews.
  """
  def get_team_by_name(name) do
    case Repo.get_by(Acai.Teams.Team, name: name) do
      nil -> {:error, :not_found}
      team -> {:ok, team}
    end
  end

  @doc """
  Gets a product by team and name (case-insensitive), returns {:ok, product} or {:error, :not_found}.

  Non-raising version for safe lookups in LiveViews.
  """
  def get_product_by_team_and_name(%Acai.Teams.Team{} = team, name) do
    case Repo.one(
           from p in Product,
             where: p.team_id == ^team.id,
             where: fragment("lower(?)", p.name) == ^String.downcase(name),
             limit: 1
         ) do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @doc """
  Gets a product by team and name from an already-loaded list of products.

  This avoids a database query when products are already loaded in the socket.
  Returns {:ok, product} or {:error, :not_found}.
  """
  def get_product_from_list(products, team, name) when is_list(products) do
    downcased_name = String.downcase(name)

    case Enum.find(products, fn p ->
           p.team_id == team.id && String.downcase(p.name) == downcased_name
         end) do
      nil -> {:error, :not_found}
      product -> {:ok, product}
    end
  end

  @doc """
  Loads all data needed for the product page in a single consolidated call.

  Returns a map with:
  - :product - the product record
  - :active_implementations - list of active implementations ordered by tree
  - :features_by_name - list of %{name, description, specs} for each feature
  - :spec_impl_completion - map of {spec_id, impl_id} => %{completed, total}
  - :feature_availability - map of {feature_name, impl_id} => boolean
  - :empty? - boolean indicating if matrix should show empty state
  - :no_features? - boolean indicating no features exist
  - :no_implementations? - boolean indicating no active implementations

  This consolidates all the separate queries from load_product_data/2 into
  one context-level call that shares pre-fetched data across lookups.

  ACIDs:
  - product-view.ROUTING.2: Single batched query fetches all data
  """
  def load_product_page(%Product{} = product, opts \\ []) do
    direction = Keyword.get(opts, :direction, :ltr)

    # Fetch specs and active implementations
    specs = Acai.Specs.list_specs_for_product(product)

    active_implementations =
      Acai.Implementations.list_active_implementations(product, direction: direction)

    # Group specs by feature_name for row headers
    features_by_name =
      specs
      |> Enum.group_by(& &1.feature_name)
      |> Enum.map(fn {feature_name, feature_specs} ->
        first_spec = List.first(feature_specs)

        %{
          name: feature_name,
          description: first_spec.feature_description,
          specs: feature_specs
        }
      end)
      |> Enum.sort_by(& &1.name)

    # Get all feature names for batch availability check
    feature_names = Enum.map(features_by_name, & &1.name)

    # Compute completion and availability using shared pre-fetched data
    # This avoids rebuilding ancestry/product lookup state twice
    {spec_impl_completion, feature_availability} =
      if specs != [] and active_implementations != [] do
        Acai.Specs.batch_get_completion_and_availability(
          specs,
          feature_names,
          active_implementations
        )
      else
        {%{}, %{}}
      end

    # Empty state checks
    empty? = features_by_name == [] or active_implementations == []

    %{
      product: product,
      active_implementations: active_implementations,
      features_by_name: features_by_name,
      spec_impl_completion: spec_impl_completion,
      feature_availability: feature_availability,
      empty?: empty?,
      no_features?: features_by_name == [],
      no_implementations?: active_implementations == []
    }
  end
end
