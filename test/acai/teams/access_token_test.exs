defmodule Acai.Teams.AccessTokenTest do
  use Acai.DataCase, async: true

  import Acai.DataModelFixtures
  import Acai.AccountsFixtures

  alias Acai.Teams.AccessToken

  @valid_attrs %{
    name: "CLI Token",
    token_hash: "abc123hash",
    token_prefix: "at_abc",
    scopes: ["specs:read", "specs:write"]
  }

  describe "changeset/2" do
    # data-model.TOKENS.3
    # data-model.TOKENS.4
    # data-model.TOKENS.5
    # data-model.TOKENS.6
    test "valid with required fields" do
      cs = AccessToken.changeset(%AccessToken{}, @valid_attrs)
      assert cs.valid?
    end

    test "invalid without required fields" do
      cs = AccessToken.changeset(%AccessToken{}, %{})
      refute cs.valid?
      errors = errors_on(cs)
      assert errors[:name]
      assert errors[:token_hash]
      assert errors[:token_prefix]
    end

    # data-model.TOKENS.6-1
    test "scopes defaults to the standard set when not provided" do
      assert %AccessToken{}.scopes == [
               "specs:read",
               "specs:write",
               "states:read",
               "states:write",
               "refs:read",
               "refs:write",
               "impls:read",
               "impls:write",
               "team:read"
             ]
    end

    test "scopes field accepts custom scope values" do
      cs =
        AccessToken.changeset(%AccessToken{}, %{
          @valid_attrs
          | scopes: ["specs:read", "team:read"]
        })

      assert cs.valid?
    end

    # data-model.TOKENS.7
    # data-model.TOKENS.8
    # data-model.TOKENS.9
    test "accepts optional timestamp fields" do
      now = DateTime.utc_now(:second)
      future = DateTime.add(now, 3600, :second)

      cs =
        AccessToken.changeset(
          %AccessToken{},
          Map.merge(@valid_attrs, %{
            expires_at: future,
            revoked_at: now,
            last_used_at: now
          })
        )

      assert cs.valid?
    end

    # data-model.TOKENS.1
    test "uses UUIDv7 primary key" do
      assert AccessToken.__schema__(:primary_key) == [:id]
      assert AccessToken.__schema__(:type, :id) == Acai.UUIDv7
    end
  end

  describe "database constraints" do
    # data-model.TOKENS.4-1
    test "token_hash must be unique" do
      user = user_fixture()
      team = team_fixture()
      access_token_fixture(team, user, %{token_hash: "unique-hash"})

      {:error, cs} =
        AccessToken.changeset(%AccessToken{}, %{@valid_attrs | token_hash: "unique-hash"})
        |> Ecto.Changeset.put_change(:team_id, team.id)
        |> Ecto.Changeset.put_change(:user_id, user.id)
        |> Acai.Repo.insert()

      assert %{token_hash: [_ | _]} = errors_on(cs)
    end
  end
end
