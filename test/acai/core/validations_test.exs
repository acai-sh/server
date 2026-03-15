defmodule Acai.Core.ValidationsTest do
  use ExUnit.Case, async: true

  import Ecto.Changeset
  import Acai.Core.Validations

  defp changeset(data) do
    types = %{name: :string, key: :string}
    {%{}, types} |> cast(data, [:name, :key])
  end

  # data-model.TEAMS.2-1
  # data-model.SPECS.7-1
  # data-model.SPECS.9-1
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
end
