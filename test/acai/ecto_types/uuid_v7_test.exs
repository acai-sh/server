defmodule Acai.UUIDv7Test do
  use ExUnit.Case, async: true

  # data-model.FIELDS.2
  describe "Acai.UUIDv7" do
    test "type/0 returns :uuid" do
      assert Acai.UUIDv7.type() == :uuid
    end

    test "autogenerate/0 returns a valid UUID v7 string" do
      id = Acai.UUIDv7.autogenerate()
      assert is_binary(id)
      assert String.length(id) == 36
      # UUID v7: version nibble at position 14 must be "7"
      assert String.at(id, 14) == "7"
      # UUID v7: variant nibble at position 19 must be 8, 9, a, or b
      assert String.at(id, 19) in ~w(8 9 a b)
    end

    test "autogenerate/0 generates unique IDs" do
      ids = for _ <- 1..10, do: Acai.UUIDv7.autogenerate()
      assert length(Enum.uniq(ids)) == 10
    end

    test "autogenerate/0 is time-ordered — later IDs sort lexicographically after earlier ones" do
      # UUIDv7 embeds a millisecond timestamp in the most-significant bits,
      # so string comparison reflects insertion order.
      id1 = Acai.UUIDv7.autogenerate()
      # ensure we cross a millisecond boundary
      Process.sleep(2)
      id2 = Acai.UUIDv7.autogenerate()

      assert id1 < id2
    end

    test "cast/1 accepts a valid UUID string" do
      id = Acai.UUIDv7.autogenerate()
      assert {:ok, ^id} = Acai.UUIDv7.cast(id)
    end

    test "cast/1 returns :error for invalid input" do
      assert :error = Acai.UUIDv7.cast("not-a-uuid")
    end

    test "equal?/2 returns true for same value" do
      id = Acai.UUIDv7.autogenerate()
      assert Acai.UUIDv7.equal?(id, id)
    end
  end
end
