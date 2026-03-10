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
end
