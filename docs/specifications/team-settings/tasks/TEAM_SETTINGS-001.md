# TEAM_SETTINGS-001 — Team Settings `/t/:team_id/settings` LiveView

## Overview

Implement the `/t/:team_id/settings` LiveView page where a team owner can rename their team or permanently delete it. The route must be gated to users with the `team:admin` scope (owner role only). Non-owners must be redirected away from the route. The page provides two modal flows: Rename Team and Delete Team.

## Acceptance Criteria

| ACID | Requirement |
|------|-------------|
| `TEAM_SETTINGS.MAIN.1` | Renders the current team name |
| `TEAM_SETTINGS.MAIN.2` | Renders a 'Rename Team' button that opens the Rename Team modal |
| `TEAM_SETTINGS.MAIN.3` | Renders a 'Delete Team' button that opens the Delete Team modal |
| `TEAM_SETTINGS.RENAME.1` | Renders a text input pre-filled with the current team name |
| `TEAM_SETTINGS.RENAME.2` | Renders Save and Cancel buttons |
| `TEAM_SETTINGS.RENAME.3` | On save, validates and persists the new team name |
| `TEAM_SETTINGS.RENAME.3-1` | Displays inline error messages on validation failure (rules defined in DATA.TEAMS) |
| `TEAM_SETTINGS.RENAME.3-2` | On success, closes the modal and reflects the updated name on the page without a full reload |
| `TEAM_SETTINGS.DELETE.1` | Educates the user that deleting the team is permanent and will cascade-delete all associated data, including implementations, specs, requirements, members, and access tokens |
| `TEAM_SETTINGS.DELETE.2` | Renders a confirmation text input requiring the user to type the exact team name before deletion is permitted |
| `TEAM_SETTINGS.DELETE.3` | Renders a 'Delete Team' confirm button, disabled until the confirmation input matches the team name exactly |
| `TEAM_SETTINGS.DELETE.4` | Renders a Cancel button that dismisses the modal without taking action |
| `TEAM_SETTINGS.DELETE.5` | On confirmed deletion, deletes the team and redirects the user to /teams |
| `TEAM_SETTINGS.AUTH.1` | The /t/:team_id/settings route is only accessible to users with the 'team:admin' scope (owner role) |
| `TEAM_SETTINGS.AUTH.2` | Users without 'team:admin' scope must be redirected away from this route |

## Context & Existing Building Blocks

### Router
- File: `lib/acai_web/router.ex`
- The new route belongs inside the existing `live_session :require_authenticated_user` block (within the `pipe_through [:browser, :require_authenticated_user]` scope), alongside the existing `/t/:team_id` route:
  ```
  live "/t/:team_id/settings", TeamSettingsLive
  ```
- The scope is already aliased to `AcaiWeb`, so the module will be `AcaiWeb.TeamSettingsLive`.
- **Auth guard (`TEAM_SETTINGS.AUTH.1` / `.AUTH.2`)**: Authentication at the `live_session` level only ensures the user is logged in — it does **not** enforce owner-only access. The permission check must be done inside `mount/3` on the LiveView. Fetch the current user's role for the team and use `Permissions.has_permission?(role, "team:admin")` to decide. If access is denied, redirect to `/t/:team_id` (or `/teams`) using `Phoenix.LiveView.redirect/2` and `:halt` the socket.

### Teams Context
- File: `lib/acai/teams/teams.ex`
- `Teams.get_team!(id)` — fetches a team by id, raises if not found.
- `Teams.update_team(team, attrs)` — already exists. Updates `name` through `Team.changeset/2`. Returns `{:ok, updated_team}` or `{:error, changeset}`. Use this for the rename flow.
- `Teams.change_team(team, attrs \\ %{})` — already exists. Returns a changeset for the team. Use this to build the rename form via `to_form(Teams.change_team(team))`.
- `Teams.list_team_members(team)` — returns all `UserTeamRole` rows for the team. Use this in mount to find the current user's role for the team.
- **Delete team**: Elixir's `Repo.delete/1` on the `%Team{}` struct will cascade-delete all related rows (roles, tokens, specs, implementations, etc.) because the DB foreign keys are `ON DELETE CASCADE` by default (per `DATA` model). Add a `delete_team/1` function to `Teams` context that simply calls `Repo.delete(team)`.

### Team Schema & Validations
- File: `lib/acai/teams/team.ex`
- `Team.changeset/2` enforces: `name` is required, lowercased, URL-safe (alphanumeric, hyphens, underscores only), and unique. Inline errors from this changeset will cover `TEAM_SETTINGS.RENAME.3-1` automatically when you use `<.input field={@form[:field]}>`.

### Permissions
- File: `lib/acai/teams/permissions.ex`
- `Permissions.has_permission?(role_title, "team:admin")` — only `"owner"` returns `true`.
- Use this in `mount/3` to enforce `TEAM_SETTINGS.AUTH.1/.AUTH.2`.

### Existing LiveView Patterns
- Reference: `lib/acai_web/live/team_live.ex` and `lib/acai_web/live/teams_live.ex`
- Follow the same inline modal pattern with `@show_rename_modal` / `@show_delete_modal` boolean assigns.
- Use `to_form(Teams.change_team(team))` for the rename form; use a plain string assign (e.g., `@confirm_name`) for the delete confirmation input — not a full form.
- `push_navigate/2` to `/teams` after team deletion (the team no longer exists, so `/t/:team_id` would 404).

### UI Components
- `<Layouts.app flash={@flash} current_scope={@current_scope}>` — wrap all content.
- `<.button>`, `<.button variant="primary">` — for action buttons.
- `<.input field={@form[:field]} type="text">` — for the rename input (inline errors handled automatically).
- `<.header>` — for the page title showing the team name.
- `<.icon name="hero-*" />` — for decorative icons.
- Keep all modals inline in the LiveView (no LiveComponents).

### Test Fixtures
- `Acai.DataModelFixtures.team_fixture/1` — creates a team.
- `Acai.DataModelFixtures.user_team_role_fixture(team, user, attrs)` — attaches a user to a team with a specific role. Pass `%{title: "owner"}` or `%{title: "developer"}`.
- `Acai.AccountsFixtures.user_fixture/0` — creates a user.
- `Acai.Accounts.Scope.for_user(user)` — builds a scope for tests.

## Implementation Plan

- [ ] **Add `delete_team/1`** to `lib/acai/teams/teams.ex`:
  - Accepts a `%Team{}` struct and calls `Repo.delete(team)`. Returns `{:ok, team}` or `{:error, changeset}`.

- [ ] **Create the LiveView module** at `lib/acai_web/live/team_settings_live.ex`:
  - `mount/3`:
    - Load the team with `Teams.get_team!(team_id)`.
    - Fetch all members with `Teams.list_team_members(team)` and find the current user's role title.
    - Check `Permissions.has_permission?(role_title, "team:admin")`. If `false`, redirect to `/t/:team_id` and halt.
    - Assign: `:team`, `:show_rename_modal` (false), `:rename_form` (built from `Teams.change_team(team)`), `:show_delete_modal` (false), `:confirm_name` ("").
  - Handle `"open_rename_modal"` — set `:show_rename_modal` to `true`, reset form to current team name.
  - Handle `"close_rename_modal"` — set `:show_rename_modal` to `false`.
  - Handle `"rename_team"` event (form submission):
    - Call `Teams.update_team(team, params)`.
    - On `{:ok, updated_team}`: update `:team` assign, close modal, reflect new name (`TEAM_SETTINGS.RENAME.3-2`).
    - On `{:error, changeset}`: assign updated form with errors to surface inline errors (`TEAM_SETTINGS.RENAME.3-1`).
  - Handle `"open_delete_modal"` — set `:show_delete_modal` to `true`, reset `:confirm_name` to `""`.
  - Handle `"close_delete_modal"` — set `:show_delete_modal` to `false`.
  - Handle `"update_confirm_name"` event (phx-change on the confirmation input) — update `:confirm_name` assign to enable/disable the confirm button reactively (`TEAM_SETTINGS.DELETE.3`).
  - Handle `"confirm_delete"` event:
    - Check `:confirm_name == team.name` as a safety gate (even though UI disables the button).
    - Call `Teams.delete_team(team)`.
    - On `{:ok, _}`: `push_navigate` to `/teams` (`TEAM_SETTINGS.DELETE.5`).

- [ ] **Create the LiveView template** (inline `~H` sigil):
  - `<Layouts.app flash={@flash} current_scope={@current_scope}>` wrapper.
  - Page header displaying `@team.name` (`TEAM_SETTINGS.MAIN.1`).
  - 'Rename Team' button (`TEAM_SETTINGS.MAIN.2`) — `phx-click="open_rename_modal"`.
  - 'Delete Team' button (`TEAM_SETTINGS.MAIN.3`) — `phx-click="open_delete_modal"`, styled with a danger/error variant.
  - **Rename modal** (shown when `@show_rename_modal`):
    - `<.form for={@rename_form} id="rename-team-form" phx-submit="rename_team">`.
    - `<.input field={@rename_form[:name]} type="text">` pre-filled with the current name (`TEAM_SETTINGS.RENAME.1`).
    - Save and Cancel buttons (`TEAM_SETTINGS.RENAME.2`).
  - **Delete modal** (shown when `@show_delete_modal`):
    - Warning message explaining permanent deletion and what is cascade-deleted (`TEAM_SETTINGS.DELETE.1`).
    - Plain `<input type="text">` (or `<.input>` without a form) with `phx-change="update_confirm_name"` for the team-name confirmation (`TEAM_SETTINGS.DELETE.2`). Give it a unique DOM id like `id="confirm-team-name-input"`.
    - 'Delete Team' confirm button with `disabled={@confirm_name != @team.name}` (`TEAM_SETTINGS.DELETE.3`).
    - Cancel button (`TEAM_SETTINGS.DELETE.4`).

- [ ] **Add the route** in `lib/acai_web/router.ex`:
  - Inside the existing `live_session :require_authenticated_user` block:
    ```
    live "/t/:team_id/settings", TeamSettingsLive
    ```

- [ ] **Write LiveView tests** at `test/acai_web/live/team_settings_live_test.exs`:
  - Unauthenticated access redirects to login.
  - Non-owner (developer/readonly role) is redirected away from the settings page (`TEAM_SETTINGS.AUTH.2`).
  - Owner can view the settings page with the team name displayed (`TEAM_SETTINGS.MAIN.1`).
  - Rename flow: modal opens with team name pre-filled; valid rename succeeds and updates the displayed name without a full reload; invalid name (e.g., special chars) shows inline errors.
  - Delete flow: modal opens; confirm button is disabled until the input matches the team name exactly; on confirmed deletion, user is redirected to `/teams`.
  - Use `has_element?/2` and `element/2` with DOM IDs defined in the template for all assertions.

- [ ] **Write context tests** at `test/acai/teams/teams_test.exs` (add to existing file):
  - `delete_team/1` deletes the team and returns `{:ok, team}`.

## Notes

- `Team.changeset/2` lowercases the name. When pre-filling the rename input with the existing `@team.name`, the value will already be lowercase — this is correct per `DATA.TEAMS.2`.
- For the delete confirmation (`TEAM_SETTINGS.DELETE.2`), the user must type the **exact** team name. Since team names are always lowercased on save, the stored `@team.name` is lowercase, and the comparison is a simple string equality check: `@confirm_name == @team.name`.
- For the `"update_confirm_name"` phx-change handler, the confirmation input is not part of an Ecto-backed form. Use a plain `phx-change` event with `phx-value-*` or a simple `<form phx-change="update_confirm_name">` wrapping the input, and extract the value from the event params map in the handler.
- `UserTeamRole` has no `id` primary key — if you need to stream members (you likely won't for this view), use a composite DOM id. For this view, fetching the list once in mount to determine role is sufficient.
- ACID comments in code must be the identifier **only** — no appended description text (e.g., `# TEAM_SETTINGS.RENAME.3-1` not `# TEAM_SETTINGS.RENAME.3-1 — inline error`).
- Run `mix precommit` after completing all changes and fix any issues before submitting.

---

## Review — Round 1

**Status: ACCEPTED**

All 15 acceptance criteria are implemented, annotated, and tested. 300 tests pass, precommit clean, no warnings.

### Findings

**Correctness & Coverage:** Every ACID from the feature spec is annotated in both production code and tests, with no omissions. The test suite is thorough: auth enforcement is tested for all three negative cases (developer, readonly, no role) as well as the positive owner case; the rename flow covers success, blank name, invalid characters, and duplicate name; the delete flow covers all button states, the confirmation gating, and the final deletion/redirect. Context-level tests for `delete_team/1` verify both the return value and cascade deletion.

**Auth implementation:** The `mount/3` permission guard is correct — `Permissions.has_permission?/2` is called with `nil` safely (returns `false`) for users with no role. The redirect uses `push_navigate` (not `redirect`) which results in a `{:ok, push_navigate(...)}` tuple — this is idiomatic for LiveView and is exercised by the test assertions on `{:error, {:live_redirect, ...}}`.

**Rename form:** `to_form(Teams.change_team(team))` is used for the initial form and correctly reset on open. On error, the changeset is passed through `to_form/1` to preserve errors for inline display via `<.input>`. On success, the `:team` assign is updated from the returned `updated_team`, so the page name reflects the DB-persisted (lowercased) value immediately without a full reload.

**Delete confirmation:** The `@confirm_name` string assign approach is clean and correct. The server-side guard in `confirm_delete` (re-checking `confirm_name == team.name`) is a good defensive layer beyond the disabled button.

**Code quality:** Follows all project conventions — `@impl true` decorators, ACID-only comments, inline modals, no LiveComponents, `<Layouts.app>` wrapper, proper `push_navigate` usage. Comment style is compliant (identifiers only, no description text appended).
