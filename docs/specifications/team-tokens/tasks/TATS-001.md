# TATS-001 — Team Access Tokens LiveView (`/t/:team_id/tokens`)

## Overview

Implement the `/t/:team_id/tokens` LiveView page where authenticated team members can list, create, and revoke team access tokens. Only members with the `tats:admin` scope (i.e., owners) may create or revoke tokens; any member with `team:read` may view the list. On creation the raw token is shown once and never again. A "Usage" section renders a coming-soon placeholder.

## Acceptance Criteria

| ACID | Requirement |
|------|-------------|
| `TATS.MAIN.1` | Lists all tokens that have been created for this team, by any user |
| `TATS.MAIN.1-1` | Lists the token prefix and the token name, created-by attribution, other useful metadata contained in the database (see DATA feature) |
| `TATS.MAIN.2` | User education explains that Team Access Tokens provide full read and write access to any resources in the team, except for `tats:admin` and `teams:admin` |
| `TATS.MAIN.3` | Can create a new token, with name, optional expiration timestamp (date picker) |
| `TATS.MAIN.3-1` | Cannot edit token scopes, it's the same set of scopes for all tokens |
| `TATS.MAIN.4` | On creation, user is presented with the token, and educated that they will never be able to see it again |
| `TATS.MAIN.4-1` | New token has a copy paste button and can be cleanly highlighted with click-drag or triple-mouse click |
| `TATS.MAIN.5` | Tokens can be revoked by clicking a revoke button |
| `TATS.MAIN.5-1` | Token revocation triggers confirmation |
| `TATS.USAGE.1` | Renders a mock Usage section with a "coming soon" placeholder |
| `TATS.TATSEC.1` | The system must never persist a raw token to the database or in logs |
| `TATS.TATSEC.2` | API authentication requests must hash the incoming token and query against the `token_hash` column |
| `TATS.TATSEC.3` | A token is considered invalid if `revoked_at` is not null, or if `expires_at` is in the past |
| `TATS.TATSEC.4` | Respect the `tats:admin` scope for create and revoke ops |
| `TATS.TATSEC.5` | Respect the `team:read` scope for read ops (everyone can see the list of all existing tokens and their details) |

## Context & Existing Building Blocks

### Router
- File: `lib/acai_web/router.ex`
- Add the new route inside the existing `live_session :require_authenticated_user` block, alongside `/t/:team_id` and `/t/:team_id/settings`:
  ```
  live "/t/:team_id/tokens", TeamTokensLive
  ```
- The scope is already aliased to `AcaiWeb`, so the module will be `AcaiWeb.TeamTokensLive`.

### Teams Context
- File: `lib/acai/teams/teams.ex`
- **Existing functions to reuse:**
  - `Teams.get_team!(id)` — fetches a team by id.
  - `Teams.list_team_members(team)` — returns all `UserTeamRole` rows with `:user` preloaded (useful for checking current user's role on mount).
  - `Teams.list_access_tokens(current_scope, team)` — currently returns tokens **only for the current user**. You will need to **add a new context function** (e.g., `Teams.list_team_tokens(team)`) that returns all `AccessToken` rows for the team regardless of user, with the `:user` association preloaded (for created-by attribution, `TATS.MAIN.1-1`).
  - `Teams.create_access_token(current_scope, team, attrs)` — creates a token. You will need to call this with pre-computed `token_hash` and `token_prefix` attrs.
  - `Teams.change_access_token(%AccessToken{}, attrs)` — returns a changeset for forms.
- **New functions needed:**
  - `Teams.list_team_tokens(team)` — returns all tokens for the team with `:user` preloaded, ordered by `inserted_at DESC` (newest first).
  - `Teams.revoke_token(current_scope, token)` — sets `revoked_at` to `DateTime.utc_now(:second)` via an update. Should verify token belongs to the team and check `tats:admin` permission before acting (or let the LiveView handle the permission gate and only do DB work here).

### Access Token Schema
- File: `lib/acai/teams/access_token.ex`
- Key fields: `name`, `token_hash`, `token_prefix`, `scopes` (auto-defaulted), `expires_at` (optional), `revoked_at` (optional), `last_used_at` (optional), `inserted_at`, `user_id`, `team_id`.
- The `raw_token` virtual field is already defined — use it to carry the plaintext token transiently back to the LiveView after creation (never persisted).

### Token Generation Logic
- You need to implement token generation in the context (or a dedicated private helper). The pattern:
  1. Generate a cryptographically random binary (e.g., `:crypto.strong_rand_bytes(32)`).
  2. Base-encode it (e.g., `Base.url_encode64(bytes, padding: false)`).
  3. Prefix it: `"at_" <> first_6_chars_of_encoded` → `token_prefix`.
  4. Full raw token: `"at_" <> full_encoded_string`.
  5. Hash it: `:crypto.hash(:sha256, raw_token) |> Base.encode16(case: :lower)` → `token_hash`.
  6. `TATS.TATSEC.1`: only store `token_hash` and `token_prefix`, never `raw_token`.
- Return the `raw_token` on the returned struct via the virtual field so the LiveView can display it once.

### Permissions
- File: `lib/acai/teams/permissions.ex`
- `Permissions.has_permission?(role_title, "tats:admin")` — `true` only for `"owner"`.
- `Permissions.has_permission?(role_title, "team:read")` — `true` for all valid roles.
- On mount, resolve the current user's role for this team (same pattern as `TeamLive` and `TeamSettingsLive`) and derive two boolean assigns: `can_manage_tokens?` (for create/revoke, requires `tats:admin`) and ensure the page is accessible to anyone with `team:read`.

### Existing LiveView Patterns
- Reference: `lib/acai_web/live/team_live.ex` and `lib/acai_web/live/team_settings_live.ex`
- Follow identical patterns: `stream/3` for the token list, inline modals driven by boolean assigns, `to_form/2` for all forms, ACID-only inline comments (e.g., `<%!-- TATS.MAIN.1 --%>`).
- For the "reveal token" state after creation, a dedicated assign (e.g., `:created_token`) holding the raw token string is sufficient — display it in a dedicated UI section, then clear it when the user dismisses or navigates away.

### UI Components (all globally imported via `AcaiWeb`)
- `<Layouts.app flash={@flash} current_scope={@current_scope}>` — wrap all LiveView content.
- `<.button>`, `<.button variant="primary">`, `<.button disabled={...}>` — action buttons.
- `<.input field={@form[:name]} type="text" label="Token name" />` — name input.
- `<.input field={@form[:expires_at]} type="datetime-local" label="Expiration (optional)" />` — date picker for expiry (`TATS.MAIN.3`).
- `<.header>` — page title section.
- `<.icon name="hero-*" />` — icons (e.g., `hero-key`, `hero-clipboard`, `hero-x-circle`).
- For the copy-paste button (`TATS.MAIN.4-1`), use a colocated JS hook (`:type={Phoenix.LiveView.ColocatedHook}`) that calls `navigator.clipboard.writeText(...)` on click, so you don't need an external hook file.

### Test Fixtures
- `Acai.DataModelFixtures.team_fixture/1` — creates a team.
- `Acai.DataModelFixtures.user_team_role_fixture(team, user, attrs)` — attaches a user with a role.
- `Acai.DataModelFixtures.access_token_fixture(team, user, attrs)` — creates a token directly (useful for listing tests).
- `Acai.AccountsFixtures.user_fixture/0` — creates a user.
- `Acai.Accounts.Scope.for_user(user)` — builds a scope for tests.

## Implementation Plan

- [ ] **Add context functions** to `lib/acai/teams/teams.ex`:
  - `list_team_tokens(team)` — returns all `AccessToken` rows for the team with `:user` preloaded, ordered newest-first.
  - `generate_token(current_scope, team, attrs)` — generates a raw token, hashes it, builds `token_prefix`, calls `create_access_token/3` with those computed fields, and returns `{:ok, token_with_raw}` where `raw_token` virtual field is populated, or `{:error, changeset}`.
  - `revoke_token(token)` — sets `revoked_at` on the given token struct and persists it.

- [ ] **Create the LiveView module** at `lib/acai_web/live/team_tokens_live.ex`:
  - `mount/3`:
    - Load team via `Teams.get_team!(team_id)`.
    - Resolve current user's role, derive `can_manage_tokens?` from `tats:admin` permission.
    - Stream all team tokens (`:tokens`) via `list_team_tokens/1` with `:user` preloaded.
    - Track a separate `tokens_empty?` assign.
    - Assign modal booleans: `:show_create_modal`, `:show_revoke_modal`.
    - Assign `:create_form` from `to_form(Teams.change_access_token(%AccessToken{}))`.
    - Assign `:created_token` (nil initially) for the post-creation reveal state.
    - Assign `:revoking_token` (nil initially) for the revoke confirmation modal.
  - Events:
    - `"open_create_modal"` — set `:show_create_modal` to `true`, reset form. Guard: only if `can_manage_tokens?`.
    - `"close_create_modal"` — close modal, clear `:created_token`.
    - `"validate"` — update `:create_form` with validated changeset (action `:validate`).
    - `"create_token"` — call `Teams.generate_token/3`, on success stream-insert the new token, set `:created_token` to the raw token string, keep modal open (to display it); on error update the form with errors.
    - `"dismiss_token"` — clear `:created_token`, close the create modal.
    - `"open_revoke_modal"` — set `:show_revoke_modal` to `true`, set `:revoking_token`. Guard: only if `can_manage_tokens?`.
    - `"close_revoke_modal"` — close modal, clear `:revoking_token`.
    - `"confirm_revoke"` — call `Teams.revoke_token/1`, on success stream-insert the updated (revoked) token to refresh the display; on error put a flash error.

- [ ] **Create the LiveView template** (inline `~H` sigil):
  - Wrap in `<Layouts.app flash={@flash} current_scope={@current_scope}>`.
  - Page header with team name and a "Create Token" button (disabled when `!@can_manage_tokens?`) — `TATS.TATSEC.4`.
  - User education callout explaining token scopes (`TATS.MAIN.2`): mention that tokens grant full `specs:read/write`, `refs:read/write`, `impls:read/write`, `team:read`, but do **not** include `tats:admin` or `team:admin`.
  - Token list with `phx-update="stream"` on the container:
    - For each token: display `token_prefix`, `name`, created-by user email, `inserted_at`, `expires_at` (if set), and a revoked badge when `revoked_at` is not nil (`TATS.MAIN.1-1`).
    - Revoke button per token row (disabled when `!@can_manage_tokens?` or token already revoked) — `TATS.MAIN.5`, `TATS.TATSEC.4`.
  - Empty state shown when `@tokens_empty?` is true.
  - Create Token inline modal:
    - Name input (`TATS.MAIN.3`).
    - Date-time input for optional expiration (`TATS.MAIN.3`). No scope selector — `TATS.MAIN.3-1`.
    - After successful creation, inside the modal (or replacing the form area), show the raw token in a monospace block with a copy button (colocated JS hook) and a clear warning that it will never be shown again (`TATS.MAIN.4`, `TATS.MAIN.4-1`). A "Done" button triggers `"dismiss_token"`.
  - Revoke confirmation inline modal: confirm message + Revoke / Cancel buttons (`TATS.MAIN.5-1`).
  - Usage section at the bottom with a "coming soon" placeholder (`TATS.USAGE.1`).

- [ ] **Add the route** in `lib/acai_web/router.ex`:
  - Inside the existing `live_session :require_authenticated_user` block:
    ```
    live "/t/:team_id/tokens", TeamTokensLive
    ```

- [ ] **Write context tests** at `test/acai/teams/teams_test.exs` (add to existing file):
  - `list_team_tokens/1` returns all tokens for the team with user preloaded, including tokens by other users.
  - `generate_token/3` returns `{:ok, token}` with `raw_token` populated and `token_hash` stored as SHA-256, never stores the raw value.
  - `generate_token/3` with a name and `expires_at` sets expiry correctly.
  - `revoke_token/1` sets `revoked_at` on the token.
  - Token is treated as invalid when `revoked_at` is set or `expires_at` is in the past (`TATS.TATSEC.3` — verify by inspecting the returned struct after revoke / by querying a manually expired token).

- [ ] **Write LiveView tests** at `test/acai_web/live/team_tokens_live_test.exs`:
  - Unauthenticated access redirects away.
  - Authenticated team member (`team:read`) can view the token list page.
  - Create Token button is disabled for non-owner roles (developer, readonly) — `TATS.TATSEC.4`.
  - Owner can open the create modal and see the name and expiry inputs but no scopes input — `TATS.MAIN.3-1`.
  - Submitting the create form with a valid name inserts a new token into the stream and reveals the raw token display — `TATS.MAIN.4`.
  - The raw token reveal area has a copy button element — `TATS.MAIN.4-1`.
  - Submitting create with an empty name shows a validation error.
  - Revoke button is disabled for non-owner roles — `TATS.TATSEC.4`.
  - Owner clicking Revoke opens the confirmation modal — `TATS.MAIN.5-1`.
  - Confirming revocation marks the token as revoked in the stream (revoked badge visible).
  - The usage section with "coming soon" text is rendered — `TATS.USAGE.1`.
  - Use `has_element?/2` and `element/2` with DOM IDs defined in the template.

## Notes

- `TATS.TATSEC.1`: Never log or persist `raw_token`. The virtual field is only populated on the return value of `generate_token/3` and must not be passed to `changeset/2`.
- `TATS.TATSEC.2`: Hashing for API auth is a constraint to be respected in the context — the `token_hash` column is what API auth will query against. This task does not implement API auth endpoints, but the `generate_token` function must produce a correct SHA-256 hash so future auth can rely on it.
- `TATS.TATSEC.3`: The token-validity logic (checking `revoked_at` and `expires_at`) is a constraint that belongs in the context. Expose a `valid_token?/1` helper or inline the logic in `revoke_token` and any future auth function.
- The `list_access_tokens(current_scope, team)` function already scopes by user — do **not** modify it (other code may depend on it). Add a new `list_team_tokens/1` instead.
- When streaming tokens, the DOM id for each token row should use the token's UUID: `id={token.id}`.
- For the copy-to-clipboard button, use a colocated JS hook (`.CopyToken`) scoped to the raw-token display area. The hook reads the text from a sibling element's `innerText` or a `data-token` attribute and calls `navigator.clipboard.writeText(...)`.
- ACID comments must be the identifier **only** — no appended description text (e.g., `# TATS.MAIN.1` not `# TATS.MAIN.1 — list all tokens`).
- Run `mix precommit` after completing all changes and fix any issues before submitting.

---

## Review — Round 1

**Status: ACCEPTED**

All 15 ACIDs are implemented, annotated in production code with identifier-only comments, and covered by at least one test each. 343 tests pass, precommit clean.

### Summary of findings

- **Context (`teams.ex`)**: `list_team_tokens/1`, `generate_token/3`, `revoke_token/1`, and `valid_token?/1` are all correct, well-structured, and idiomatic. Token generation follows the prescribed crypto pattern exactly (`:crypto.strong_rand_bytes/1`, SHA-256 hash, prefix extracted from encoded bytes). The raw token is correctly never stored — only populated on the virtual field of the return value.
- **LiveView (`team_tokens_live.ex`)**: Follows the established inline-modal + stream pattern from `TeamLive` and `TeamSettingsLive` precisely. Permission gates on `can_manage_tokens?` are applied correctly in both the UI (disabled buttons) and event handlers (no-op guard). The `build_token_attrs/1` helper handles the `datetime-local` format correctly.
- **Template**: All ACID annotations present and identifier-only (the single combined `<%!-- TATS.MAIN.3 / TATS.MAIN.4 --%>` is consistent with the accepted pattern already in the codebase). `select-all` CSS class on the token `<pre>` correctly satisfies `TATS.MAIN.4-1` for click-drag highlighting. Colocated `.CopyToken` JS hook is correctly scoped and named.
- **Route**: Correctly placed inside the existing `live_session :require_authenticated_user` block.
- **Tests**: Full coverage across context (`teams_test.exs`) and LiveView (`team_tokens_live_test.exs`). The ordering test was made robust by using explicit `inserted_at` timestamps via `Repo.update_all`. ACID annotations are identifier-only throughout.
