defmodule AcaiWeb.TeamsLiveTest do
  use AcaiWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Acai.AccountsFixtures
  import Acai.DataModelFixtures

  alias Acai.Teams

  describe "unauthenticated access" do
    test "redirects unauthenticated user to log in", %{conn: conn} do
      {:error, {:redirect, %{to: path}}} = live(conn, ~p"/teams")
      assert path == ~p"/users/log-in"
    end
  end

  describe "mount / empty state" do
    setup :register_and_log_in_user

    # team-list.MAIN.2-1
    test "shows empty state placeholder when user has no teams", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/teams")
      assert has_element?(view, "#teams-empty-state")
    end

    # team-list.MAIN.1
    test "renders the CREATE TEAM button in the header", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/teams")
      assert has_element?(view, "#open-create-team-modal")
    end

    test "empty state also renders a create team call-to-action button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/teams")
      assert has_element?(view, "#empty-state-create-team")
    end
  end

  describe "team list" do
    setup :register_and_log_in_user

    # team-list.MAIN.2
    test "shows teams the user belongs to as cards", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, view, _html} = live(conn, ~p"/teams")

      assert has_element?(view, "#teams-list")
      assert has_element?(view, "[id^='teams-']", team.name)
    end

    # team-list.MAIN.2-1
    test "does not show empty state when user has teams", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, view, _html} = live(conn, ~p"/teams")

      refute has_element?(view, "#teams-empty-state")
    end

    # team-list.MAIN.2-2
    test "team card links to /t/:team_name", %{conn: conn, user: user} do
      team = team_fixture()
      user_team_role_fixture(team, user, %{title: "owner"})

      {:ok, view, _html} = live(conn, ~p"/teams")

      assert has_element?(view, "a[href='/t/#{team.name}']")
    end

    test "does not show teams the user has no role in", %{conn: conn} do
      _other_team = team_fixture()

      {:ok, view, _html} = live(conn, ~p"/teams")

      assert has_element?(view, "#teams-empty-state")
    end
  end

  describe "modal" do
    setup :register_and_log_in_user

    # team-list.MAIN.1-1
    test "clicking CREATE TEAM opens the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/teams")

      refute has_element?(view, "#create-team-modal")

      view |> element("#open-create-team-modal") |> render_click()

      assert has_element?(view, "#create-team-modal")
    end

    test "clicking close button dismisses the modal", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/teams")

      view |> element("#open-create-team-modal") |> render_click()
      assert has_element?(view, "#create-team-modal")

      view |> element("#close-modal-button") |> render_click()
      refute has_element?(view, "#create-team-modal")
    end

    # team-list.CREATE.2
    test "modal renders the team name input", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/teams")
      view |> element("#open-create-team-modal") |> render_click()

      assert has_element?(view, "#create-team-form input[name='team[name]']")
    end

    # team-list.CREATE.3
    test "modal renders a submit button", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/teams")
      view |> element("#open-create-team-modal") |> render_click()

      assert has_element?(view, "#create-team-submit")
    end
  end

  describe "create team" do
    setup :register_and_log_in_user

    # team-list.CREATE.1
    test "shows validation errors for an empty name", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/teams")
      view |> element("#open-create-team-modal") |> render_click()

      view
      |> form("#create-team-form", %{"team" => %{"name" => ""}})
      |> render_change()

      assert has_element?(view, "#create-team-form", "can't be blank")
    end

    # team-list.CREATE.1 / team-list.ENG.2
    test "shows validation errors for a name that is not url-safe", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/teams")
      view |> element("#open-create-team-modal") |> render_click()

      view
      |> form("#create-team-form", %{"team" => %{"name" => "My Invalid Team!"}})
      |> render_change()

      assert has_element?(view, "#create-team-form .text-error")
    end

    # team-list.CREATE.1
    test "shows error when team name is already taken", %{conn: conn} do
      existing = team_fixture(%{name: "taken-team"})

      {:ok, view, _html} = live(conn, ~p"/teams")
      view |> element("#open-create-team-modal") |> render_click()

      view
      |> form("#create-team-form", %{"team" => %{"name" => existing.name}})
      |> render_submit()

      assert has_element?(view, "#create-team-form", "has already been taken")
    end

    # team-list.CREATE.3-1 / team-list.ENG.1
    test "successful submission navigates to /t/:team_name and assigns owner role", %{
      conn: conn,
      user: user,
      scope: scope
    } do
      {:ok, view, _html} = live(conn, ~p"/teams")
      view |> element("#open-create-team-modal") |> render_click()

      # team-list.CREATE.3-1
      assert {:error, {:live_redirect, %{to: redirect_path}}} =
               view
               |> form("#create-team-form", %{"team" => %{"name" => "my-new-team"}})
               |> render_submit()

      team = Teams.list_teams(scope) |> List.first()
      assert team.name == "my-new-team"
      assert redirect_path == "/t/#{team.name}"

      # team-list.ENG.1
      [role] = Teams.list_user_team_roles(scope, team)
      assert role.title == "owner"
      assert role.user_id == user.id
    end
  end

  describe "signed_in_path redirect" do
    # team-list.MAIN.3
    test "new user is redirected to /teams after registration (signed_in_path is /teams)", %{
      conn: conn
    } do
      user = user_fixture()

      # Visiting a page that requires auth while unauthenticated saves return_to
      # and redirects. After login, the user lands on signed_in_path which is /teams.
      # We test this by directly hitting the redirect_if_user_is_authenticated route
      # which only fires for the registration page scope.
      conn =
        conn
        |> log_in_user(user)
        |> get(~p"/users/register")

      assert redirected_to(conn) == ~p"/teams"
    end
  end
end
