# System Design & ADR
This document provides an overview of key system design decisions for acai.sh, a tool for spec-driven development.

## Product Overview

Acai.sh is a set of tools, including a webapp and JSON REST API (both in this Elixir Phoenix app), and a CLI (separate repo). The tools are used to support a spec-driven software development workflow.
- Write requirements and acceptance criteria in `feature.yaml` spec files, following a standard spec format we've invented.
- Run a CLI command to extract the specs and push them to the server. The CLI also looks for references to requirement IDs in your codebase, and records those as well.
- Use the dashboard to see a cross-sectional view of your products, features, and implementations. Drill down to see whether a requirement is represented in tests or application code.
- Annotate your projects with states (e.g. "assigned", "completed", "accepted") and comments, to empower collaboration and coordination and to effectively manage your software projects.

The result: AI agents can use the CLI to query and search requirements, specs, states, and code references across repos and implementations. This enables them to self-assign work and stay on-track. Humans can use the dashboard to monitor progress, report issues, or mark requirements as "accepted".

## Data Model

### What is a Spec?

A spec is a file like `my-feature.feature.yaml` that defines `feature.name`, `feature.product`, and a list of requirements.

```yaml
feature:
    name: my-feature
    product: my-website

components:
    EXAMPLE:
      requirements:
        1: The requirement ID for this requirement is 'my-feature.EXAMPLE.1'
        1-1: The requirement ID for this sub-requirement is 'my-feature.EXAMPLE.1-1'
```

The `specs` table maintains one row per branch-local spec identity: `branch_id` + `feature_name`. A spec is inserted when:
- A feature is first pushed to a branch
- A feature is renamed, creating a new `feature_name` on that branch

Otherwise, the existing spec row is updated. `path` is mutable metadata, `feature_version` updates in place, and `raw_content` plus `requirements` are overwritten on each successful push.

### What is an Implementation?

One product can have many implementations. An implementation is a product-wide environment defined by a set of tracked branches, with optional parent inheritance.

Examples:
- `Production` tracks `frontend/main` and `backend/main`, no parent
- `Staging` tracks `frontend/dev` and `backend/dev`, parent is `Production`
- `experiment-1` tracks `frontend/experiment` and `backend/dev`, parent is `Staging`

Core constraint:
- An implementation cannot track two branches in the same repo

The `branches` table stores stable rows per `(team_id, repo_uri, branch_name)`, enabling branch renames without breaking foreign keys. The `tracked_branches` join table associates implementations with branches they track.

### Implementation Inheritance

Supported via optional `parent_implementation_id` with `ON DELETE SET NULL`.

Inheritance behavior differs by data type:
- Specs are resolved across tracked branches, with the child's spec taking precedence when both parent and child have the same feature
- States are snapshotted from the parent on the first push for a given `(implementation_id, feature_name)`; later parent changes do not affect the child
- Code references are aggregated across tracked branches, walking up the parent chain when needed

New implementations are created automatically when specs are pushed to an untracked branch, and the default implementation name is the branch name.

## Data Model

This section summarizes the schema implemented in `priv/repo/migrations/20260308000000_setup_database.exs`.

### Key Tables

| Table | Purpose | Key Constraints |
|-------|---------|-----------------|
| `teams` | Top-level tenant for RBAC and billing | Unique name, URL-safe chars only |
| `products` | Collection of features | Unique `(team_id, name)` |
| `access_tokens` | API access tokens with scoped permissions | Unique `token_hash` |
| `user_team_roles` | Team membership join table | Unique `(team_id, user_id)` role assignment |
| `implementations` | Product-wide environments with optional inheritance | Unique `(product_id, name)`; parent uses `ON DELETE SET NULL` |
| `branches` | Stable branch identity | Unique `(team_id, repo_uri, branch_name)` |
| `tracked_branches` | Implementation ↔ Branch join table | Unique `(implementation_id, repo_uri)` |
| `specs` | Branch-local spec files | Unique `(branch_id, feature_name)` |
| `feature_impl_states` | Requirement states per feature + implementation | GIN index on JSONB states |
| `feature_branch_refs` | Code references per feature + branch | GIN index on JSONB refs |

Both `feature_impl_states` and `feature_branch_refs` are keyed by `feature_name` (the requirement ID prefix), not `spec_id`. This allows pushing states and code references without a local spec file, which is useful for monorepos where specs live in a different repo than the implementing code.

`access_tokens.scopes` is stored as a non-null JSONB field in the database. Default scopes are assigned by application code rather than by a database default.

### Standard Fields

All tables described by this data model include `created_at` and `updated_at` timestamps. Primary keys are stored in `uuid` columns and generated as UUIDv7 values by the application, except `user_team_roles`, which has no `id` primary key.

## CLI (MVP)

Most use-cases are covered by `acai push`:
- `acai push`: Git-aware push of changed specs and code references only
- `acai push --all`: Full repo scan and push (useful for setup or major drift)

## API (MVP)

### POST /api/v1/push

**Authentication**: Bearer token with vanilla access token generated in UI.

**Key Behaviors**:
- All operations are atomic; any failure rolls back the entire push
- Push is idempotent
- Partial pushes merge with existing data
- First state write snapshots from parent, then merges

**Common Rejection Scenarios**:
- Multi-product push
- States without implementation
- Implementation name collision
- Branch tracked by different implementation

## Key User Journeys

All journeys work locally, on CI (GitHub Actions), or via git hooks:
- Update existing spec
- Add new spec
- Delete or rename a feature or product
- Edit code or tests, creating new code references
- Change implementation state
- Mix spec, code reference, and state changes in a single push

## Edge Cases

| Case | Behavior | Note |
|------|----------|------|
| Orphaned states | Retained for reinstatement | Retained data |
| Dangling code references | Allowed, persisted if format valid | Valid reference shape only |
| Spec rename | New spec created; old preserved | New feature identity |
| Parent deleted | Child survives | `ON DELETE SET NULL` |
| First state write | Snapshot from parent, then merge | Copy-on-first-write |
| Override mode | Replace entire bucket | Full bucket replacement |
| Concurrent pushes | Last-write-wins | Latest successful write |
