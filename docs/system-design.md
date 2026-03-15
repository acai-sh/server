# System Design & ADR

This document provides an overview of key system design decisions for acai.sh, a tool for spec-driven development.

Acai.sh is a CLI and API that supports a spec-driven development workflow:
- Write requirements and acceptance criteria in `feature.yaml` spec files
- Run a CLI command to extract Acceptance Criteria IDs (ACIDs) and push them to a server
- Use the dashboard, CLI, and API to track implementation progress and conduct structured QA

The result: AI agents can more easily query and search requirements, specs, states, and code refs across repos and implementations, helping them self-assign work and stay on-track. Humans get a cross-sectional view of their products, feature specs, and AI agent changes.

## Mental Model

### What is a Spec?

A spec is a file like `my-feature.feature.yaml` that defines `feature.name`, `feature.product`, and a list of requirements.

```yaml
feature:
    name: my-feature
    product: my-website

components:
    EXAMPLE:
      requirements:
        1: The ACID for this requirement is 'my-feature.EXAMPLE.1'
        1-1: The ACID for this sub-requirement is 'my-feature.EXAMPLE.1-1'
```

A spec can have multiple versions on different git branches with different `feature.version` numbers. The `specs` table maintains one row per branch-local spec identity (see `data-model.SPEC_IDENTITY`). A spec is inserted when:
- Product name + feature name combo is new (brand new feature)
- Branch + version is new (branched refactoring of existing feature)

Otherwise, existing specs are updated. The `path`, `version`, `raw_content`, and `requirements` map are all mutable per `data-model.SPEC_IDENTITY.4`.

### What is an Implementation?

One product can have many implementations. An implementation is a group of tracked branches with optional parent inheritance per `data-model.INHERITANCE`.

Examples:
- `Production` tracks `frontend/main` and `backend/main`, no parent
- `Staging` tracks `frontend/dev` and `backend/dev`, parent is `Production`
- `experiment-1` tracks `frontend/experiment` and `backend/dev`, parent is `Staging`

Constraints per `data-model.TRACKED_BRANCHES.4`:
- feature.yaml files must be pushed from tracked branches or parent implementation's tracked branches
- An implementation cannot track two branches in the same repo

The `branches` table stores stable rows per `(team_id, repo_uri, branch_name)` per `data-model.BRANCHES.6-1`, enabling branch renames without breaking foreign keys. The `tracked_branches` join table associates implementations with branches they track.

### Implementation Inheritance

Supported via optional `parent_implementation_id` with `ON DELETE SET NULL` per `data-model.IMPLS.7-1`. Inheritance allows quick branch/implementation creation without losing parent refs, status updates, and specs.

We use lazy inheritance: states and refs are resolved by traversing the parent chain on each query per `data-model.INHERITANCE.2`, not snapshotted at creation. This trades potential staleness (when child branches drift from parent) for write performance. Developers can always do a full push from the child branch or pull upstream git changes.

New implementations are created automatically when pushing from an untracked branch per `push.NEW_IMPLS.1`.

## Data Model

See `setup_database.exs` for the schema and `data-model.feature.yaml` for the full spec.

### Key Tables

| Table | Purpose | Key Constraints |
|-------|---------|-----------------|
| `teams` | Top-level tenant for RBAC and billing | Unique name, URL-safe chars only (`data-model.TEAMS.2-1`) |
| `products` | Collection of features | Unique `(team_id, name)` per `data-model.PRODUCTS.6` |
| `branches` | Stable branch identity | Unique `(team_id, repo_uri, branch_name)` per `data-model.BRANCHES.6-1` |
| `tracked_branches` | Implementation ↔ Branch join table | Unique `(implementation_id, repo_uri)` per `data-model.TRACKED_BRANCHES.4` |
| `specs` | Branch-local spec files | Unique `(branch_id, feature_name)` per `data-model.SPECS.12` |
| `feature_impl_states` | ACID states per feature + implementation | GIN index on JSONB states per `data-model.FEATURE_IMPL_STATES.6` |
| `feature_branch_refs` | Code refs per feature + branch | GIN index on JSONB refs per `data-model.FEATURE_BRANCH_REFS.8` |

Both `feature_impl_states` and `feature_branch_refs` are keyed by `feature_name` (ACID prefix), not `spec_id`. This allows pushing states/refs without a local spec file—useful for monorepos where specs live in a different repo than the implementing code.

### Standard Fields

All tables include `created_at` and `updated_at` timestamps per `data-model.FIELDS.1`. All entities use UUIDv7 primary keys per `data-model.FIELDS.2`, except `user_team_roles`.

## CLI (MVP)

Most use-cases are covered by `acai push`:
- `acai push`: Git-aware push of changed specs/refs only
- `acai push --all`: Full repo scan and push (useful for setup or major drift)

## API (MVP)

### POST /api/v1/push

See `push.feature.yaml` for the full spec.

**Authentication**: Bearer token with vanilla access token generated in UI.

**Key Behaviors**:
- All operations are atomic per `push.TX.1`—any failure rolls back the entire push
- Push is idempotent per `push.IDEMPOTENCY.1`
- Partial pushes merge with existing data per `push.WRITE_STATES.3` and `push.REFS.5`
- First state write snapshots from parent then merges per `push.WRITE_STATES.2`

**Common Rejection Scenarios**:
- Multi-product push (`push.NEW_IMPLS.4`)
- States without implementation (`push.NEW_IMPLS.2`)
- Implementation name collision (`push.NEW_IMPLS.5`)
- Branch tracked by different implementation (`push.EXISTING_IMPLS.4`)

## Key User Journeys

All journeys work locally, on CI (GitHub Actions), or via git hooks:
- Update existing spec (`push.UPDATE_SPEC`)
- Add new spec (`push.INSERT_SPEC`)
- Delete/rename feature or product (`data-model.SPEC_IDENTITY.3`)
- Edit code/tests → new refs (`push.WRITE_REFS`)
- Change implementation state (`push.WRITE_STATES`)
- Mixed changes in single commit (`push.TX.1`)

## Edge Cases

| Case | Behavior | ACID |
|------|----------|------|
| Orphaned states | Retained for reinstatement | `push.WRITE_STATES.4` |
| Dangling refs | Allowed, persisted if format valid | `push.REFS.3` |
| Spec rename | New spec created; old preserved | `data-model.SPEC_IDENTITY.3` |
| Parent deleted | Child survives (SET NULL) | `data-model.IMPLS.7-1` |
| First state write | Snapshot from parent, then merge | `push.WRITE_STATES.2` |
| Override mode | Replace entire bucket | `push.REFS.6`, `push.STATES.1` |
| Concurrent pushes | Last-write-wins | `push.TX.2` |
