defmodule Acai.Teams.PermissionsTest do
  use ExUnit.Case, async: true

  alias Acai.Teams.Permissions

  @all_scopes ~w(specs:read specs:write states:read states:write refs:read refs:write impls:read impls:write team:read team:admin tats:admin)

  describe "valid_roles/0" do
    # team-roles.SCOPES.1
    test "returns the three supported roles" do
      assert Permissions.valid_roles() == ~w(readonly developer owner)
    end
  end

  describe "scopes_for/1" do
    # team-roles.SCOPES.3
    # team-roles.SCOPES.4
    test "owner has all scopes" do
      scopes = Permissions.scopes_for("owner")

      for scope <- @all_scopes do
        assert scope in scopes, "expected owner to have #{scope}"
      end
    end

    # team-roles.SCOPES.5
    test "developer has all scopes except team:admin and tats:admin" do
      scopes = Permissions.scopes_for("developer")

      expected_scopes = @all_scopes -- ~w(team:admin tats:admin)

      for scope <- expected_scopes do
        assert scope in scopes, "expected developer to have #{scope}"
      end

      refute "team:admin" in scopes
      refute "tats:admin" in scopes
    end

    # team-roles.SCOPES.6
    test "readonly only has read scopes" do
      scopes = Permissions.scopes_for("readonly")

      assert "specs:read" in scopes
      assert "states:read" in scopes
      assert "refs:read" in scopes
      assert "impls:read" in scopes
      assert "team:read" in scopes
      refute "specs:write" in scopes
      refute "states:write" in scopes
      refute "refs:write" in scopes
      refute "impls:write" in scopes
      refute "team:admin" in scopes
      refute "tats:admin" in scopes
    end

    test "unknown role returns empty list" do
      assert Permissions.scopes_for("superadmin") == []
    end
  end

  describe "has_permission?/2" do
    # team-roles.MODULE.1
    # team-roles.SCOPES.4
    test "owner has permission for every scope" do
      for scope <- @all_scopes do
        assert Permissions.has_permission?("owner", scope),
               "expected owner to have #{scope}"
      end
    end

    # team-roles.SCOPES.5
    test "developer does not have team:admin" do
      refute Permissions.has_permission?("developer", "team:admin")
    end

    test "developer does not have tats:admin" do
      refute Permissions.has_permission?("developer", "tats:admin")
    end

    test "developer has specs:write" do
      assert Permissions.has_permission?("developer", "specs:write")
    end

    test "developer has states:read and states:write" do
      assert Permissions.has_permission?("developer", "states:read")
      assert Permissions.has_permission?("developer", "states:write")
    end

    # team-roles.SCOPES.6
    test "readonly has specs:read" do
      assert Permissions.has_permission?("readonly", "specs:read")
    end

    test "readonly has states:read" do
      assert Permissions.has_permission?("readonly", "states:read")
    end

    test "readonly does not have states:write" do
      refute Permissions.has_permission?("readonly", "states:write")
    end

    test "readonly does not have specs:write" do
      refute Permissions.has_permission?("readonly", "specs:write")
    end

    test "readonly does not have team:admin" do
      refute Permissions.has_permission?("readonly", "team:admin")
    end

    test "unknown role has no permissions" do
      refute Permissions.has_permission?("ghost", "specs:read")
    end
  end
end
