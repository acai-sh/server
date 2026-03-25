# System Design & ADR
This document provides an overview of key system design decisions for acai.sh, a tool for spec-driven development.

## Product Overview

Acai.sh is a set of tools including a server (a containerized web app and JSON REST API) and a CLI. The tools support a spec-driven software development workflow:

1. Write requirements and acceptance criteria in `feature.yaml` spec files, following a standard spec format. The spec serves as the central source of truth for feature functionality and for what constitutes acceptable implementation in code.
2. Run a CLI command to extract the specs and push them to the server. The CLI also scans for references to requirement IDs in your codebase and records those as well.
3. Humans can view the dashboard and agents can query the server (via CLI commands). This provides a cross-sectional view of your products, features, and implementations — useful for QA assessment of AI-generated code and for enabling agents to self-assign work, respond to spec changes, and coordinate across large, ambitious, long-running projects.

## Data Model

### What is a Spec?

A spec is a file like `my-feature.feature.yaml` that defines `feature.name`, `feature.product`, and a list of requirements. A spec always belongs to a product, e.g. `mobile-app`, `web-app`, `api`, `cli`.

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

The `specs` table maintains one row per branch-local spec identity: `branch_id` + `feature_name`. A spec row is inserted when:
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
- An implementation cannot track two branches from the same repo

The `branches` table stores stable rows per `(team_id, repo_uri, branch_name)`, enabling branch renames without breaking foreign keys. The `tracked_branches` join table associates implementations with the branches they track.

### Implementation Inheritance

Supported via optional `parent_implementation_id` with `ON DELETE SET NULL`.

Inheritance behavior:
- **Specs** are resolved across tracked branches, with the child's spec taking precedence when both parent and child track the same feature.
- **Code references** are aggregated across tracked branches, walking up the parent chain when needed.

New implementations are created automatically when specs are pushed to an untracked branch; the default implementation name is the branch name. Parent must be explicitly specified at creation time via `parent_impl_name` — there is no auto-inheritance.

## Schema

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

Both `feature_impl_states` and `feature_branch_refs` are keyed by `feature_name` (the requirement ID prefix), not `spec_id`. This allows pushing code references without a local spec file, which is useful for products where specs live in a different repo than the implementing code.

`access_tokens.scopes` is stored as a non-null JSONB field. Default scopes are assigned by application code rather than by a database default.

### Standard Fields

All tables include `created_at` and `updated_at` timestamps. Primary keys are `uuid` columns generated as UUIDv7 values by the application, except `user_team_roles`, which has no `id` primary key.

## CLI

Most use cases are covered by `acai push`:
- `acai push`: Git-aware push of changed specs and code references only
- `acai push --all`: Full repo scan and push (useful for initial setup or after significant drift)

### Multi-Product Push (Monorepo)

The API accepts only one product per call. In multi-product monorepos, the CLI splits specs by product and makes individual API calls.

Namespacing supports `product-name/impl-name` format for `--target` and `--parent` flags. The CLI strips the `product-name/` prefix before sending each per-product API call.

#### New branch, no parent, no targets
CLI splits by product. Server creates the product, implementation, inserts specs and refs, tracks the branch.

#### New branch, with parents
CLI accepts `--parent product-a/parent-name product-b/parent-name`. If a spec can't be mapped to a parent, the API rejects.

#### New branch, with parents and targets
CLI accepts `--parent product-a/parent-name product-b/parent-name` and `--target product-a/new-impl product-b/new-impl`. Server creates implementations with inheritance.

#### Any of the above, filtered by `feature-name`
Fewer specs/refs included in the payload. Note: work on one feature can cause regressions in another, so `push --all` is encouraged.

#### Existing tracked branch
- No parent/target: updates specs and refs as usual
- With parent: parent is ignored (idempotent, parent is immutable after creation)
- With target: API rejects if branch is tracked by a different implementation

## API

### POST /api/v1/push

**Authentication**: Bearer token using a vanilla access token generated in the UI.

**Key Behaviors**:
- All operations are atomic; any failure rolls back the entire push
- Push is idempotent
- Partial pushes merge with existing data

**Common Rejection Scenarios**:
- Multi-product push (specs span multiple products)
- Implementation name collision within a product
- Branch already tracked by a different implementation than the given target
- `parent_impl_name` provided on an existing tracked branch (parent is immutable after creation)

## Key User Journeys

All journeys work locally, on CI (GitHub Actions), or via git hooks:
- Update an existing spec
- Add a new spec
- Delete or rename a feature or product
- Edit code or tests, creating new code references
- Push specs and code references in a single call

## Edge Cases

| Case | Behavior | Note |
|------|----------|------|
| Dangling code references | Allowed; persisted if format is valid | Valid reference shape only |
| Spec rename | New spec created; old preserved | New feature identity |
| Parent deleted | Child survives | `ON DELETE SET NULL` |
| Override mode | Replace entire bucket | Full bucket replacement |
| Concurrent pushes | Last-write-wins | Latest successful write |

## Decisions

- **Multi-product**: `push --all` pushes all specs for all products. The CLI splits into per-product API calls since the API only accepts one product at a time.
- **Refs always included**: Filters (`feature-name`, future `product-name`) also apply to refs to reduce payload size. However, `push --all` is encouraged since work on one feature can cause regressions in another.
- **No impl creation from already-tracked branches**: We do not support creation of a new implementation via push from a branch that is already tracked by a different implementation. The user can accomplish this by editing tracked branches.
