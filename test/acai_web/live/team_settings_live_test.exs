defmodule AcaiWeb.TeamSettingsLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.DataModelFixtures

  alias Acai.Teams

  defp create_team_with_owner(user) do
    team = team_fixture()
    _role = user_team_role_fixture(team, user, %{title: "owner"})
    team
  end

  describe "unauthenticated access" do
    test "redirects to log-in", %{conn: conn} do
      team = team_fixture()
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/t/#{team.name}/settings")
      assert path == ~p"/users/log-in"
    end
  end

  describe "authorization" do
    setup :register_and_log_in_user

    # team-settings.AUTH.2
    test "redirects developer away from settings", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "developer"})

      {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/t/#{team.name}/settings")
      assert path == "/t/#{team.name}"
    end

    # team-settings.AUTH.2
    test "redirects readonly user away from settings", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "readonly"})

      {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/t/#{team.name}/settings")
      assert path == "/t/#{team.name}"
    end

    # team-settings.AUTH.2
    test "redirects a user with no role away from settings", %{conn: conn} do
      team = team_fixture()
      {:error, {:live_redirect, %{to: path}}} = live(conn, ~p"/t/#{team.name}/settings")
      assert path == "/t/#{team.name}"
    end

    # team-settings.AUTH.1
    test "owner can access the settings page", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, _view, _html} = live(conn, ~p"/t/#{team.name}/settings")
    end
  end

  describe "main page" do
    setup :register_and_log_in_user

    # team-settings.MAIN.1
    test "renders the current team name", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")
      assert has_element?(view, "h1", team.name)
    end

    # team-settings.MAIN.2
    test "renders the Rename Team button", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")
      assert has_element?(view, "#rename-team-btn")
    end

    # team-settings.MAIN.3
    test "renders the Delete Team button", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")
      assert has_element?(view, "#delete-team-btn")
    end
  end

  describe "rename modal" do
    setup :register_and_log_in_user

    # team-settings.MAIN.2
    test "clicking Rename Team button opens the rename modal", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      refute has_element?(view, "#rename-modal")
      view |> element("#rename-team-btn") |> render_click()
      assert has_element?(view, "#rename-modal")
    end

    test "closing the rename modal hides it", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#rename-team-btn") |> render_click()
      assert has_element?(view, "#rename-modal")

      view |> element("#close-rename-modal-btn") |> render_click()
      refute has_element?(view, "#rename-modal")
    end

    test "cancel button closes the rename modal", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#rename-team-btn") |> render_click()
      view |> element("#cancel-rename-btn") |> render_click()
      refute has_element?(view, "#rename-modal")
    end

    # team-settings.RENAME.1
    test "rename modal renders a text input pre-filled with the current team name", %{
      conn: conn,
      user: user
    } do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#rename-team-btn") |> render_click()

      assert has_element?(view, "#rename-team-form input[type='text']")
      assert has_element?(view, "#rename-team-form input[value='#{team.name}']")
    end

    # team-settings.RENAME.2
    test "rename modal renders Save and Cancel buttons", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#rename-team-btn") |> render_click()

      assert has_element?(view, "#save-rename-btn")
      assert has_element?(view, "#cancel-rename-btn")
    end

    # team-settings.RENAME.3
    # team-settings.RENAME.3-2
    test "valid rename persists and reflects the updated name without a full reload", %{
      conn: conn,
      user: user
    } do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#rename-team-btn") |> render_click()

      view
      |> form("#rename-team-form", %{"team" => %{"name" => "new-team-name"}})
      |> render_submit()

      refute has_element?(view, "#rename-modal")
      assert has_element?(view, "h1", "new-team-name")
    end

    # team-settings.RENAME.3-1
    test "shows inline error when name contains invalid characters", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#rename-team-btn") |> render_click()

      view
      |> form("#rename-team-form", %{"team" => %{"name" => "invalid name!"}})
      |> render_submit()

      assert has_element?(view, "#rename-modal")
      assert has_element?(view, "#rename-team-form", "only")
    end

    # team-settings.RENAME.3-1
    test "shows inline error when name is blank", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#rename-team-btn") |> render_click()

      view
      |> form("#rename-team-form", %{"team" => %{"name" => ""}})
      |> render_submit()

      assert has_element?(view, "#rename-modal")
      assert has_element?(view, "#rename-team-form", "can't be blank")
    end

    # team-settings.RENAME.3-1
    test "shows inline error when name is already taken", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      other_team = team_fixture()
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#rename-team-btn") |> render_click()

      view
      |> form("#rename-team-form", %{"team" => %{"name" => other_team.name}})
      |> render_submit()

      assert has_element?(view, "#rename-modal")
      assert has_element?(view, "#rename-team-form", "has already been taken")
    end
  end

  describe "delete modal" do
    setup :register_and_log_in_user

    # team-settings.MAIN.3
    test "clicking Delete Team button opens the delete modal", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      refute has_element?(view, "#delete-modal")
      view |> element("#delete-team-btn") |> render_click()
      assert has_element?(view, "#delete-modal")
    end

    test "closing the delete modal hides it", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#delete-team-btn") |> render_click()
      assert has_element?(view, "#delete-modal")

      view |> element("#close-delete-modal-btn") |> render_click()
      refute has_element?(view, "#delete-modal")
    end

    # team-settings.DELETE.4
    test "cancel button dismisses the delete modal without deleting", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#delete-team-btn") |> render_click()
      view |> element("#cancel-delete-btn") |> render_click()

      refute has_element?(view, "#delete-modal")
      assert Acai.Repo.get(Acai.Teams.Team, team.id)
    end

    # team-settings.DELETE.1
    test "delete modal educates user about permanent cascade-deletion", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#delete-team-btn") |> render_click()

      assert has_element?(view, "#delete-modal", "permanent")
      assert has_element?(view, "#delete-modal", "Implementations")
      assert has_element?(view, "#delete-modal", "Specs")
      assert has_element?(view, "#delete-modal", "Members")
      assert has_element?(view, "#delete-modal", "Access tokens")
    end

    # team-settings.DELETE.2
    test "delete modal renders a confirmation text input", %{conn: conn, user: user} do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#delete-team-btn") |> render_click()
      assert has_element?(view, "#confirm-team-name-input")
    end

    # team-settings.DELETE.3
    test "confirm delete button is disabled when confirmation input is empty", %{
      conn: conn,
      user: user
    } do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#delete-team-btn") |> render_click()
      assert has_element?(view, "#confirm-delete-team-btn[disabled]")
    end

    # team-settings.DELETE.3
    test "confirm delete button is disabled when confirmation input does not match team name", %{
      conn: conn,
      user: user
    } do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#delete-team-btn") |> render_click()

      view
      |> element("form[phx-change='update_confirm_name']")
      |> render_change(%{"confirm_name" => "wrong-name"})

      assert has_element?(view, "#confirm-delete-team-btn[disabled]")
    end

    # team-settings.DELETE.3
    test "confirm delete button is enabled when confirmation input matches team name exactly", %{
      conn: conn,
      user: user
    } do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#delete-team-btn") |> render_click()

      view
      |> element("form[phx-change='update_confirm_name']")
      |> render_change(%{"confirm_name" => team.name})

      refute has_element?(view, "#confirm-delete-team-btn[disabled]")
    end

    # team-settings.DELETE.5
    test "on confirmed deletion, deletes the team and redirects to /teams", %{
      conn: conn,
      user: user
    } do
      team = create_team_with_owner(user)
      {:ok, view, _html} = live(conn, ~p"/t/#{team.name}/settings")

      view |> element("#delete-team-btn") |> render_click()

      view
      |> element("form[phx-change='update_confirm_name']")
      |> render_change(%{"confirm_name" => team.name})

      assert {:error, {:live_redirect, %{to: "/teams"}}} =
               view |> element("#confirm-delete-team-btn") |> render_click()

      assert is_nil(Acai.Repo.get(Teams.Team, team.id))
    end
  end
end
