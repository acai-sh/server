defmodule Acai.UUIDv7 do
  @moduledoc """
  A custom Ecto.Type wrapping the `UUIDv7` library for use as a primary key type.

  # data-model.FIELDS.2 - All entities use UUIDv7 primary keys

  Usage in schemas:
      @primary_key {:id, Acai.UUIDv7, autogenerate: true}
      @foreign_key_type Acai.UUIDv7
  """

  use Ecto.Type

  # Delegate to the UUIDv7 library's Ecto.Type implementation

  @impl Ecto.Type
  def type, do: UUIDv7.type()

  @impl Ecto.Type
  def cast(value), do: UUIDv7.cast(value)

  @impl Ecto.Type
  def load(value), do: UUIDv7.load(value)

  @impl Ecto.Type
  def dump(value), do: UUIDv7.dump(value)

  @impl Ecto.Type
  def autogenerate, do: UUIDv7.autogenerate()

  @impl Ecto.Type
  def equal?(a, b), do: UUIDv7.equal?(a, b)

  @impl Ecto.Type
  def embed_as(format), do: UUIDv7.embed_as(format)
end
