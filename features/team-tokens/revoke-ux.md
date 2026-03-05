# Task: revoke-ux

Implement the REVOKE component requirements from the `team-tokens` feature spec. Revoked tokens must be separated from active tokens into their own collapsible section with revocation metadata.

## Acceptance Criteria

- [ ] `team-tokens.REVOKE.1` — Revoked tokens are excluded from Tokens list and rendered in a separate Revoked Tokens list
- [ ] `team-tokens.REVOKE.2` — They indicate the revocation date, show a Revoked badge
- [ ] `team-tokens.REVOKE.3` — The Revoked Tokens list is collapsable and is collapsed by default

## Current State

The current implementation in `lib/acai_web/live/team_tokens_live.ex` uses a single stream (`:tokens`) that renders all tokens — both active and revoked — into one `#tokens-list` container. Revoked tokens already display a "Revoked" badge inline and have their revoke button disabled, but they are not separated from active tokens.

The context function `Teams.list_team_tokens/1` in `lib/acai/teams/teams.ex` (line 224) fetches all tokens for a team with no filtering on `revoked_at`.

## Implementation Plan

### 1. Context layer — split the query

In `lib/acai/teams/teams.ex`, the existing `list_team_tokens/1` currently returns all tokens. You need to either:
- Add a new function (e.g. `list_revoked_team_tokens/1`) that queries only `where: not is_nil(t.revoked_at)`, OR
- Add a filter parameter to the existing function

Also update `list_team_tokens/1` to exclude revoked tokens (add `where: is_nil(t.revoked_at)`).

Both queries should maintain the existing `order_by: [desc: t.inserted_at]` and `preload: [:user]` patterns.

### 2. LiveView mount — two separate streams

In `lib/acai_web/live/team_tokens_live.ex`, update `mount/3` to:
- Fetch active tokens (non-revoked) and revoked tokens separately
- Set up two streams: `:tokens` for active tokens, and a new stream (e.g. `:revoked_tokens`) for revoked ones
- Add an assign to track whether the revoked section is expanded (collapsed by default per `REVOKE.3`)
- Update the `:tokens_empty?` assign to only consider active tokens

### 3. LiveView event — handle revocation stream transfer

In the `confirm_revoke` handler (line 144), after a token is successfully revoked:
- Remove the token from the `:tokens` stream using `stream_delete/3`
- Insert the revoked token into the `:revoked_tokens` stream using `stream_insert/3`
- Update the empty-state tracking assigns as needed

Also add a new event handler for toggling the revoked section's collapsed/expanded state.

### 4. Template — separate sections

In the `render/1` function, update the template to:
- Keep the existing `#tokens-list` for active-only tokens (remove the inline revoked badge and revoke-disabled logic from this list since revoked tokens won't appear here)
- Add a new collapsible "Revoked Tokens" section below the active tokens list (and above the Usage section)
  - Use a `<details>`/`<summary>` element or a toggle assign + click handler for the collapse behavior (collapsed by default per `REVOKE.3`)
  - Give the section a unique DOM id (e.g. `#revoked-tokens-section`)
  - Use a `phx-update="stream"` container (e.g. `#revoked-tokens-list`) for the revoked tokens stream
  - Each revoked token row should show: name, prefix, created-by, and the **revocation date** (`revoked_at` formatted like the other dates), plus a "Revoked" badge (`REVOKE.2`)

### 5. Tests

Update and add tests in `test/acai_web/live/team_tokens_live_test.exs`:
- **`REVOKE.1`**: Verify that revoked tokens do NOT appear in `#tokens-list`; verify they DO appear in the revoked tokens section
- **`REVOKE.2`**: Verify revoked tokens show the revocation date and a "Revoked" badge in the revoked section
- **`REVOKE.3`**: Verify the revoked section is collapsed by default; verify it can be expanded via interaction

Update context tests in `test/acai/teams/teams_test.exs`:
- Update existing `list_team_tokens/1` tests if the query changes to exclude revoked tokens
- Add tests for the new revoked-tokens query function

### Existing test notes

The existing test `"revoked token shows revoked badge in the list"` (line 292 in team_tokens_live_test.exs) and `"revoke button is disabled for already-revoked tokens"` (line 303) assert against `#tokens-list` and will need to be updated to reflect the new separation. The test for confirming revocation (line 274) asserts the DB state and should remain valid.

## Key Files

| File | Role |
|------|------|
| `lib/acai/teams/teams.ex` | Context — query functions for active vs revoked tokens |
| `lib/acai_web/live/team_tokens_live.ex` | LiveView — mount, events, template |
| `test/acai_web/live/team_tokens_live_test.exs` | LiveView tests |
| `test/acai/teams/teams_test.exs` | Context tests |
| `lib/acai/teams/access_token.ex` | Schema reference (has `revoked_at` field) |
| `test/support/fixtures/data_model_fixtures.ex` | `access_token_fixture/3` — already supports `revoked_at` attr |
