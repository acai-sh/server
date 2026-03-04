defmodule Acai.Core.ValidationsTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset
  import Acai.Core.Validations

  defp changeset(data) do
    types = %{name: :string, key: :string}
    {%{}, types} |> cast(data, [:name, :key])
  end

  # data-model.TEAMS.2-1
  # data-model.SPECS.8-1
  # data-model.SPECS.12-1
  describe "validate_url_safe/2" do
    test "accepts alphanumeric characters" do
      cs = changeset(%{name: "hello123"}) |> validate_url_safe(:name)
      assert cs.valid?
    end

    test "accepts hyphens" do
      cs = changeset(%{name: "hello-world"}) |> validate_url_safe(:name)
      assert cs.valid?
    end

    test "accepts underscores" do
      cs = changeset(%{name: "hello_world"}) |> validate_url_safe(:name)
      assert cs.valid?
    end

    test "rejects spaces" do
      cs = changeset(%{name: "hello world"}) |> validate_url_safe(:name)
      refute cs.valid?
    end

    test "rejects special characters" do
      cs = changeset(%{name: "hello@world"}) |> validate_url_safe(:name)
      refute cs.valid?
    end

    test "passes empty string (validate_required handles blank, not validate_url_safe)" do
      cs = changeset(%{name: ""}) |> validate_url_safe(:name)
      # validate_format skips empty strings; validate_required is responsible for blanks
      assert cs.valid?
    end
  end

  # data-model.FIELDS.2
  describe "validate_uppercase_key/2" do
    test "accepts uppercase alphanumeric characters" do
      cs = changeset(%{key: "COMPONENT1"}) |> validate_uppercase_key(:key)
      assert cs.valid?
    end

    test "accepts underscores" do
      cs = changeset(%{key: "MY_KEY"}) |> validate_uppercase_key(:key)
      assert cs.valid?
    end

    test "rejects lowercase" do
      cs = changeset(%{key: "mykey"}) |> validate_uppercase_key(:key)
      refute cs.valid?
    end

    test "rejects hyphens" do
      cs = changeset(%{key: "MY-KEY"}) |> validate_uppercase_key(:key)
      refute cs.valid?
    end

    test "rejects spaces" do
      cs = changeset(%{key: "MY KEY"}) |> validate_uppercase_key(:key)
      refute cs.valid?
    end
  end
end
