defmodule Acai.Products.Product do
  use Ecto.Schema
  import Ecto.Changeset
  import Acai.Core.Validations

  # data-model.PRODUCTS.1
  # data-model.FIELDS.2
  @primary_key {:id, Acai.UUIDv7, autogenerate: true}
  @foreign_key_type Acai.UUIDv7

  schema "products" do
    # data-model.PRODUCTS.2
    belongs_to :team, Acai.Teams.Team
    # data-model.PRODUCTS.3
    field :name, :string
    # data-model.PRODUCTS.4
    field :description, :string
    # data-model.PRODUCTS.5
    field :is_active, :boolean, default: true

    timestamps(type: :utc_datetime)
  end

  @required_fields [:name, :team_id]
  @optional_fields [:description, :is_active]

  @doc false
  def changeset(product, attrs) do
    product
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    # data-model.PRODUCTS.3-1
    |> validate_url_safe(:name)
    |> check_constraint(:name, name: :products_name_url_safe)
    # data-model.PRODUCTS.6
    |> unique_constraint([:team_id, :name])
  end
end
