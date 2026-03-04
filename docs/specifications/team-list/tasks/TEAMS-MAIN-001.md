# TEAMS-MAIN-001 — Teams List View & Create Team Modal

## Overview

Implement the `/teams` LiveView page where authenticated users can view their teams as cards, create a new team via a modal form, and navigate to a team's detail page. This is also the landing page for new users after registration.

## Acceptance Criteria

| ACID | Requirement |
|------|-------------|
| `TEAMS.MAIN.1` | Renders a CREATE TEAM button |
| `TEAMS.MAIN.1-1` | On click, opens a Create Team modal |
| `TEAMS.MAIN.2` | Renders a list of teams for which the user has a role as cards |
| `TEAMS.MAIN.2-1` | Show a call to action placeholder if the user has not yet created their first team |
| `TEAMS.MAIN.2-2` | On click of the team card, it navigates to `/t/:team_id` |
| `TEAMS.MAIN.3` | This is the view that a new user sees when they first create an account |
| `TEAMS.CREATE.1` | Shows error messages if team name is rejected or invalid or fails to create |
| `TEAMS.CREATE.2` | Renders an input for the team name |
| `TEAMS.CREATE.3` | Renders a submit button |
| `TEAMS.CREATE.3-1` | On submit, navigates the user to their newly created team at `/t/:team_id` |
| `TEAMS.ENG.1` | The user who creates the team must receive the owner role for that team by default |
| `TEAMS.ENG.2` | Rely on schema/changesets for validation and error handling |

## Context & Existing Building Blocks

### Router
- File: `lib/acai_web/router.ex`
- The authenticated route scope uses `pipe_through [:browser, :require_authenticated_user]` — place the `/teams` LiveView route here.
- `signed_in_path` currently redirects to `~p"/"`. After this task, update `signed_in_path/1` in `lib/acai_web/user_auth.ex` to redirect to `~p"/teams"` so new users land on the teams page (satisfies `TEAMS.MAIN.3`).

### Teams Context
- File: `lib/acai/teams/teams.ex`
- `Teams.list_teams(current_scope)` — returns teams where the user has any role (ready to use).
- `Teams.create_team(current_scope, attrs)` — creates a team **and** inserts an `owner` `UserTeamRole` in one transaction (satisfies `TEAMS.ENG.1`).
- `Teams.change_team(%Team{}, attrs)` — returns a changeset for forms.

### Team Schema & Validation
- File: `lib/acai/teams/team.ex`
- The `:name` field is validated: required, lowercased, URL-safe, and unique (satisfies `TEAMS.ENG.2`).
- Errors from the changeset will surface via `<.input>` automatically.

### Scope
- `current_scope` is set by the `:fetch_current_scope_for_user` plug already in the `:browser` pipeline.
- Access the user via `current_scope.user`.

### UI Components (all imported globally via `AcaiWeb`)
- `<Layouts.app flash={@flash} current_scope={@current_scope}>` — wrap all LiveView content with this.
- `<.button>` / `<.button variant="primary">` — use for the CREATE TEAM button and modal submit button.
- `<.input field={@form[:name]} type="text" label="Team name" />` — use inside the create form.
- `<.header>` — available for page title/actions section.
- `<.icon name="hero-*" />` — use for icons (e.g., placeholder empty state).

### Test Fixtures
- `Acai.DataModelFixtures.team_fixture/1` — creates a team directly (no user role).
- `Acai.DataModelFixtures.user_team_role_fixture(team, user, attrs)` — attaches a user to a team with a role.
- `Acai.AccountsFixtures` — `user_fixture/0` for creating users.
- Use `Acai.Accounts.Scope.for_user(user)` to build a scope in tests.

## Implementation Plan

- [ ] **Create the LiveView module** at `lib/acai_web/live/teams_live.ex`
  - Mount: load `Teams.list_teams(current_scope)` into a stream (`:teams`)
  - Track a separate assign for empty state (e.g., `:teams_empty?`)
  - Assign a `to_form(Teams.change_team(%Team{}))` as `:form` for the modal
  - Track modal open/close state with a `:show_modal` boolean assign
  - Handle `"open_modal"` event → set `:show_modal` to `true`, reset the form
  - Handle `"close_modal"` event → set `:show_modal` to `false`
  - Handle `"validate"` event → update `:form` with a validated changeset (action `:validate`)
  - Handle `"create_team"` event → call `Teams.create_team/2`, on success navigate to `~p"/t/#{team.id}"`, on error update the form with errors

- [ ] **Create the LiveView template** (inline `~H` sigil or `.html.heex` file)
  - Wrap all content in `<Layouts.app flash={@flash} current_scope={@current_scope}>`
  - Page header with a CREATE TEAM button (`phx-click="open_modal"`, id `"open-create-team-modal"`)
  - Team card grid using `phx-update="stream"` on the container
    - Each card navigates to `/t/:team_id` on click (use `<.link navigate={~p"/t/#{team.id}"}>`)
    - Display the team name prominently
  - Empty state placeholder rendered conditionally when `@teams_empty?` is true
  - Create Team modal (conditionally shown via `@show_modal`)
    - Rendered inside the page (not a separate component)
    - Form with id `"create-team-form"`, `phx-change="validate"`, `phx-submit="create_team"`
    - `<.input field={@form[:name]} ...>` for team name
    - Submit button and a close/cancel button (`phx-click="close_modal"`)
    - Display changeset errors automatically via `<.input>`

- [ ] **Add the route** in `lib/acai_web/router.ex`
  - Inside the `pipe_through [:browser, :require_authenticated_user]` scope:
    ```
    live "/teams", TeamsLive
    ```

- [ ] **Update `signed_in_path/1`** in `lib/acai_web/user_auth.ex`
  - Change the return value from `~p"/"` to `~p"/teams"` so post-login and post-registration redirects land on the teams page (satisfies `TEAMS.MAIN.3`)

- [ ] **Write tests** at `test/acai_web/live/teams_live_test.exs`
  - Test that an unauthenticated user is redirected away from `/teams`
  - Test that an authenticated user with no teams sees the empty state placeholder
  - Test that an authenticated user sees their teams as cards
  - Test that clicking CREATE TEAM opens the modal
  - Test that submitting the form with an invalid name shows errors
  - Test that submitting the form with a valid name navigates to `/t/:team_id`
  - Use `has_element?/2` and `element/2` with the DOM IDs you define in the template

## Notes

- The `/t/:team_id` route does **not** need to exist yet — `push_navigate` to it is enough to satisfy `TEAMS.MAIN.2-2` and `TEAMS.CREATE.3-1`; Phoenix will show a 404 until that feature is built.
- Team names are stored lowercased and must be URL-safe (enforced by changeset) — make sure the UI reflects any relevant label/hint.
- Do **not** use LiveComponents for the modal — keep it inline in the LiveView.
- Keep streams for the team list; track `teams_empty?` as a separate assign since streams are not enumerable.
