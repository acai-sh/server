# TEAM-001 — Team View `/t/:team_id` LiveView

## Overview

Implement the `/t/:team_id` LiveView page where authenticated team members can see team details, manage members (invite, edit roles, delete members), and navigate to related sub-pages (tokens, settings). This view is the central hub for a team.

## Acceptance Criteria

| ACID | Requirement |
|------|-------------|
| `TEAM.MAIN.1` | Renders the team name |
| `TEAM.MAIN.2` | Renders an Access Tokens card that takes the user to `/t/:team_id/tokens` |
| `TEAM.MAIN.3` | Renders a Team Settings button that navigates the user to `/t/:team_id/settings` |
| `TEAM.MEMBERS.1` | Renders a list of members and their roles |
| `TEAM.MEMBERS.2` | Renders an 'Invite' button that triggers the Invite Member Modal |
| `TEAM.MEMBERS.2-1` | Invite button is disabled if user does not have permission (see ROLES) |
| `TEAM.MEMBERS.3` | Renders an 'Edit' button that triggers the Edit role modal |
| `TEAM.MEMBERS.3-1` | Edit button is disabled if user does not have team admin permissions (see ROLES) |
| `TEAM.MEMBERS.3-2` | Only an owner may edit their own role, and only if they are not the last owner |
| `TEAM.EDIT_ROLE.1` | Renders Save and Cancel buttons |
| `TEAM.EDIT_ROLE.2` | Renders a dropdown to change the user's role |
| `TEAM.EDIT_ROLE.3` | Saves are applied immediately and silently |
| `TEAM.DELETE_ROLE.1` | Renders Save and Delete buttons |
| `TEAM.DELETE_ROLE.2` | Educates the user what will happen when they press delete (user access revoked, tokens revoked) |
| `TEAM.DELETE_ROLE.3` | Revokes all access tokens that user has created for the team |
| `TEAM.DELETE_ROLE.4` | Prevents the user from deleting the last owner of the team |
| `TEAM.INVITE.1` | Renders an email input |
| `TEAM.INVITE.2` | Renders a dropdown selector for the desired role (default: 'developer') |
| `TEAM.INVITE.3` | Renders a 'Send Invitation' button |
| `TEAM.INVITE.3-1` | Returns an error if the invitee is already a member of the team |
| `TEAM.INVITE.3-2` | Creates a user record for that email if none exists |
| `TEAM.INVITE.3-3` | Sends the invitee an email inviting them to create an account or notifying them they were added |
| `TEAM.INVITE.3-4` | No acceptance state — if the user already has an account they are immediately added to the team |

## Context & Existing Building Blocks

### Router
- File: `lib/acai_web/router.ex`
- Place the new route inside the existing `live_session :require_authenticated_user` block (within the `pipe_through [:browser, :require_authenticated_user]` scope), alongside the existing `/teams` route:
  ```
  live "/t/:team_id", TeamLive
  ```
- The scope is already aliased to `AcaiWeb`, so the module will be `AcaiWeb.TeamLive`.

### Teams Context
- File: `lib/acai/teams/teams.ex`
- `Teams.get_team!(id)` — fetches a team by id, raises if not found.
- `Teams.list_user_team_roles(current_scope, team)` — currently **only returns the current user's roles**, not all team members. You will need to **add a new context function** (e.g., `Teams.list_team_members(team)`) that returns all `UserTeamRole` rows for the team, with the associated user preloaded (for displaying email addresses).
- `Teams.update_member_role(current_scope, role, new_title)` — updates a member's role. Guards against self-demotion (`{:error, :self_demotion}`) and last-owner demotion (`{:error, :last_owner}`). Returns `{:ok, updated_role}` or `{:error, reason_or_changeset}`.
- `Teams.create_user_team_role(current_scope, team, attrs)` — adds a user to a team with a role. Note this currently scopes to `current_scope.user.id`; you will need to **add a new function** for invite flows that accepts an arbitrary `user_id` rather than relying on `current_scope`.
- You will need to **add a delete/remove-member function** to the Teams context that removes a `UserTeamRole` row and revokes all `AccessToken`s the removed user created for that team (sets `revoked_at`).

### Permissions
- File: `lib/acai/teams/permissions.ex`
- `Permissions.has_permission?(role, scope_tag)` — use this to gate UI elements.
- Invite button requires `"team:admin"` scope.
- Edit button requires `"team:admin"` scope, with the additional restriction that owners can only edit their own role if they are not the last owner (`TEAM.MEMBERS.3-2`).
- Check the current user's role for the team (fetched on mount) to determine which buttons are enabled/disabled.

### Accounts Context
- File: `lib/acai/accounts.ex`
- `Accounts.get_user_by_email(email)` — returns `%User{}` or `nil`. Use this in the invite flow to check if the user exists.
- `Accounts.register_user(attrs)` — creates a user record. For invites where no account exists, use this to create a stub account (email only — the user will complete registration via magic link). Since `register_user/1` uses `email_changeset`, which does not require a password, this should work for stubs.
- `Accounts.deliver_login_instructions(user, magic_link_url_fun)` — sends a magic-link email. Use this for newly created stub users so they can log in and complete setup (satisfies `TEAM.INVITE.3-3` for the "create account" path).
- For existing users who are already confirmed, you only need to notify them they were added (a simple email is sufficient; no magic link needed).

### UserNotifier
- File: `lib/acai/accounts/user_notifier.ex`
- You will likely need to **add a new deliver function** for team invites (e.g., `deliver_team_invite_instructions(user, team_name, login_url)`) to satisfy `TEAM.INVITE.3-3`. Follow the same pattern as the existing delivery functions.

### AccessToken Schema
- File: `lib/acai/teams/access_token.ex`
- `revoked_at` field is a `:utc_datetime`. Revoking means setting `revoked_at` to `DateTime.utc_now(:second)` for all tokens where `user_id == removed_user.id AND team_id == team.id`.

### User Schema
- File: `lib/acai/accounts/user.ex`
- Has `:email`, `:confirmed_at`. No password is required for registration (magic-link auth is used).

### UserTeamRole Schema
- File: `lib/acai/teams/user_team_role.ex`
- `@primary_key false` — no `id` field. Keyed on `(team_id, user_id)`.
- Has `belongs_to :user` and `belongs_to :team`.
- `changeset/2` validates `:title` inclusion via `Permissions.valid_roles()`.

### Existing LiveView Pattern
- Reference: `lib/acai_web/live/teams_live.ex`
- Follow the same patterns: `stream/3` for collections, inline modal pattern with `@show_modal` booleans, `to_form/2` for all forms, ACID-only inline comments (e.g., `# TEAM.INVITE.3-1`).

### UI Components
- `<Layouts.app flash={@flash} current_scope={@current_scope}>` — wrap all content.
- `<.button>`, `<.button variant="primary">`, `<.button disabled={...}>` — use for all action buttons.
- `<.input field={@form[:field]} type="select" options={...}>` — use for role dropdown selectors.
- `<.header>` — for the page title.
- `<.icon name="hero-*" />` — for decorative icons.
- **Do not use LiveComponents** — keep all modals inline in the LiveView.

### Test Fixtures
- `Acai.DataModelFixtures.team_fixture/1` — creates a team.
- `Acai.DataModelFixtures.user_team_role_fixture(team, user, attrs)` — attaches a user to a team with a role.
- `Acai.AccountsFixtures.user_fixture/0` — creates a user.
- `Acai.Accounts.Scope.for_user(user)` — builds a scope for tests.

## Implementation Plan

- [ ] **Add context functions** to `lib/acai/teams/teams.ex`:
  - `list_team_members(team)` — returns all `UserTeamRole` rows for the team with `:user` preloaded.
  - `invite_member(team, email, role, invite_url_fn)` — find-or-create user by email, create role (error if already a member), send appropriate email.
  - `remove_member(current_scope, team, user_id)` — delete the `UserTeamRole`, revoke all `AccessToken`s for that user/team combo. Guard against removing the last owner.

- [ ] **Add email delivery function** to `lib/acai/accounts/user_notifier.ex`:
  - `deliver_team_invite_instructions(user, team_name, login_url)` for new users (magic link).
  - `deliver_team_added_notification(user, team_name)` for existing confirmed users (simple notification, no magic link).

- [ ] **Create the LiveView module** at `lib/acai_web/live/team_live.ex`:
  - `mount/3`: load team, all members (stream), current user's role for permission checks. Assign modal state booleans (`:show_invite_modal`, `:show_edit_modal`, `:show_delete_modal`) and the selected member being acted on.
  - Handle `"invite_member"` event → call context invite function, handle errors (already member, etc.).
  - Handle `"edit_role"` / `"save_role"` events → call `Teams.update_member_role/3`, handle `{:error, :self_demotion}` and `{:error, :last_owner}`.
  - Handle `"delete_member"` / `"confirm_delete"` events → call `remove_member/3`, re-stream members on success.
  - All modal forms should use `to_form/2`; errors surfaced via `<.input>`.

- [ ] **Create the LiveView template** (inline `~H` sigil):
  - `<Layouts.app flash={@flash} current_scope={@current_scope}>` wrapper.
  - Page header displaying `@team.name` (`TEAM.MAIN.1`).
  - Access Tokens card linking to `/t/:team_id/tokens` (`TEAM.MAIN.2`) — the route does not need to exist yet; a `<.link navigate>` is sufficient.
  - Team Settings button linking to `/t/:team_id/settings` (`TEAM.MAIN.3`) — same.
  - Members list with `phx-update="stream"` showing each member's email and role.
  - Invite button (disabled based on `team:admin` permission).
  - Edit button per member row (disabled based on `team:admin` permission and last-owner guard).
  - Inline Invite modal (email input + role dropdown + Send Invitation button).
  - Inline Edit Role modal (role dropdown + Save/Cancel).
  - Inline Delete Member modal (confirmation text + Delete/Cancel).

- [ ] **Add the route** in `lib/acai_web/router.ex`:
  - Inside the existing `live_session :require_authenticated_user` block:
    ```
    live "/t/:team_id", TeamLive
    ```

- [ ] **Write tests** at `test/acai_web/live/team_live_test.exs`:
  - Unauthenticated access is redirected.
  - Team member (any role) can view team name, members list.
  - Invite button is disabled for non-admin users.
  - Invite flow: error if already a member; success creates role and shows confirmation.
  - Edit role flow: success updates the role silently; `{:error, :self_demotion}` and `{:error, :last_owner}` show appropriate errors.
  - Delete member flow: last-owner cannot be deleted; revokes tokens on success.
  - Use `has_element?/2` and `element/2` with DOM IDs defined in the template.

- [ ] **Write context tests** at `test/acai/teams/teams_test.exs`:
  - `list_team_members/1` returns all members with user preloaded.
  - `invite_member/4` creates a new user if none exists; errors if already a member.
  - `remove_member/3` deletes role and revokes tokens; guards last owner.

## Notes

- The `/t/:team_id/tokens` and `/t/:team_id/settings` routes do **not** need to exist yet — link to them but Phoenix will 404 until those features are built.
- Keep all modals inline (no LiveComponents).
- `UserTeamRole` has no `id` primary key — when streaming members, use a composite key like `"member-#{role.user_id}"` for DOM ids.
- When editing a member's own role (owner self-edit), disable the Edit button unless they are not the last owner — this is enforced at context level too, but the UI should reflect it preemptively (`TEAM.MEMBERS.3-2`).
- ACID comments in code must be the identifier **only** — no appended description text (e.g., `# TEAM.INVITE.3-1` not `# TEAM.INVITE.3-1 — already a member check`).
- Run `mix precommit` after completing all changes and fix any issues before submitting.
