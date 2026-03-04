# ROLES-001 — Permissions Module & Role-Scope Enforcement

## Context

The `team-roles` feature requires a centralized `Permissions` module that encodes the mapping of hardcoded team roles (`readonly`, `developer`, `owner`) to their respective access scopes, and enforces the constraint that a team always has at least one owner.

The data layer is already in place: the `user_team_roles` table and `Acai.Teams.UserTeamRole` schema exist (`DATA.ROLES` prerequisite is satisfied). The `title` field on `UserTeamRole` currently accepts any string — this task adds the role/scope logic layer on top.

---

## Objective

Implement the `Acai.Permissions` module that:
- Defines the three supported roles and their scope sets
- Exposes a `has_permission?(role, scope_tag)` predicate
- Is the single source of truth for all role/scope logic in the codebase

Additionally, extend the `Acai.Teams` context to enforce that an owner cannot demote themselves and that the last owner on a team cannot be demoted.

---

## Acceptance Criteria

| ACID | Requirement |
|---|---|
| `ROLES.SCOPES.1` | Supported roles are `readonly`, `developer`, and `owner` |
| `ROLES.SCOPES.2` | Every team member must have a role |
| `ROLES.SCOPES.3` | Supported scopes are `specs:read`, `specs:write`, `refs:read`, `refs:write`, `impls:read`, `impls:write`, `team:read`, `team:admin`, `tats:admin` |
| `ROLES.SCOPES.4` | `owner` role has all scopes |
| `ROLES.SCOPES.5` | `developer` has all scopes excluding `team:admin` and `tats:admin` |
| `ROLES.SCOPES.6` | `readonly` role only has `specs:read`, `refs:read`, `impls:read`, `team:read` |
| `ROLES.SCOPES.7` | An owner cannot demote themselves, but can demote any other owner |
| `ROLES.MODULE.1` | Permissions logic is always accessed via a Permissions module e.g. `Permissions.has_permission?(role, scope_tag)` |
| `ROLES.MODULE.2` | Mapping of roles to scopes is hardcoded in the Permissions module |
| `ROLES.MODULE.3` | Team must always have one owner; last owner cannot demote themselves |

---

## Action Items

- [ ] Create `lib/acai/teams/permissions.ex` as `Acai.Teams.Permissions` (or `Acai.Permissions` — pick a consistent location inside the `acai` context boundary)
  - [ ] Hardcode the role-to-scopes mapping for all three roles (`ROLES.SCOPES.1`, `ROLES.SCOPES.3–6`, `ROLES.MODULE.2`)
  - [ ] Expose `scopes_for(role)` returning the list of scope strings for a given role
  - [ ] Expose `has_permission?(role, scope_tag)` returning a boolean (`ROLES.MODULE.1`)
  - [ ] Expose `valid_roles()` returning the list of supported role strings (`ROLES.SCOPES.1`)
- [ ] Update `Acai.Teams.UserTeamRole.changeset/2` to validate that `title` is one of the supported roles (`ROLES.SCOPES.1`, `ROLES.SCOPES.2`)
- [ ] Add a `update_member_role/3` (or similarly named) function to `Acai.Teams` context:
  - [ ] Accepts `current_scope`, the target `%UserTeamRole{}`, and the new role string
  - [ ] Enforces the self-demotion guard: if the acting user is the same as the target user and both are `owner`, reject the change (`ROLES.SCOPES.7`, `ROLES.MODULE.3`)
  - [ ] Enforces the last-owner guard: if the role being changed is `owner` and they are the only owner on the team, reject the change (`ROLES.MODULE.3`)
- [ ] Write unit tests in `test/acai/teams/permissions_test.exs`
  - [ ] Assert `has_permission?/2` returns correct results for all three roles against representative scopes
  - [ ] Assert `scopes_for/1` returns the exact expected set for each role
  - [ ] Assert `valid_roles/0` returns the three supported roles
- [ ] Write unit tests in `test/acai/teams/teams_test.exs` (or a new `update_member_role_test.exs`) covering:
  - [ ] Happy path: owner successfully demotes another owner
  - [ ] Error case: owner attempts to demote themselves (`ROLES.SCOPES.7`)
  - [ ] Error case: last owner on a team attempts to change their own role (`ROLES.MODULE.3`)
  - [ ] Happy path: owner promotes a `readonly` member to `developer`
- [ ] Ensure `UserTeamRole` changeset test is updated to cover validation of invalid role strings

---

## Relevant Files

| File | Notes |
|---|---|
| `lib/acai/teams/user_team_role.ex` | Add role title validation using `validate_inclusion/3` against `Permissions.valid_roles()` |
| `lib/acai/teams/teams.ex` | Add `update_member_role/3`; import/alias the new Permissions module |
| `lib/acai/teams/permissions.ex` | **New file** — core of this task |
| `test/acai/teams/permissions_test.exs` | **New file** — unit tests for the Permissions module |
| `test/acai/teams/user_team_role_test.exs` | Extend with role validation tests |
| `test/acai/teams/teams_test.exs` | Extend with role update / owner guard tests |

---

## Key Patterns & Notes

- The `Acai.Teams` context already handles `create_team/2` and seeds the creator as `"owner"`. Once `UserTeamRole.changeset/2` validates `title`, this will be automatically enforced on all writes.
- The Permissions module should be **pure Elixir** — no DB calls, no side effects. Just data and predicates.
- The last-owner check in `update_member_role/3` will require a DB query: count `owner` roles for the team before allowing the change. Query through `Acai.Repo` inside the Teams context (keep DB logic out of the Permissions module).
- `ROLES.SCOPES.7` and `ROLES.MODULE.3` overlap but are distinct guards. Implement both explicitly with clear, separate error returns/tuples (e.g., `{:error, :self_demotion}` vs `{:error, :last_owner}`).
- No LiveView or UI work is in scope for this task — purely the context and module layer.

---

## Review — ACCEPTED

**Reviewer:** Senior Engineer
**Date:** 2026-03-04
**Outcome:** ✅ ACCEPTED

### Summary

All 10 ACIDs from the spec are implemented and annotated correctly. The implementation is clean, idiomatic Elixir, and all 208 tests pass with zero failures.

### Findings

**Correctness — all ACIDs satisfied:**
- `ROLES.SCOPES.1–6`, `ROLES.MODULE.1–2`: `Acai.Teams.Permissions` is a pure compile-time module with hardcoded `@role_scopes` map and correct scope sets for all three roles.
- `ROLES.SCOPES.2`: `UserTeamRole.changeset/2` validates `title` via `validate_inclusion/3` against `Permissions.valid_roles()`.
- `ROLES.SCOPES.7` and `ROLES.MODULE.3`: Both guards are present in `update_member_role/3` as separate, clearly-named error tuples (`:self_demotion` and `:last_owner`).

**Code quality — no issues:**
- `Permissions` module is pure Elixir with no side effects. Scope subtraction for `developer` via `@all_scopes -- ~w(team:admin tats:admin)` is clean and self-documenting.
- `update_member_role/3` correctly handles the no-primary-key constraint on `UserTeamRole` by using `Repo.update_all/2` with a `(team_id, user_id)` filter, then returning a manually updated struct.
- ACID comments are present on all relevant lines without duplicating spec text.

**Tests — thorough:**
- All three roles are tested in both `scopes_for/1` and `has_permission?/2` with positive and negative assertions.
- `teams_test.exs` covers all guard paths and happy paths for `update_member_role/3`.
- Fixture default `"member"` was correctly updated to `"readonly"` to keep the shared fixture consistent with the new validation.

**No issues found.**
