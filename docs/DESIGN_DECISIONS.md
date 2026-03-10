# Design Decisions

Key design decisions for the feature specification tracking system. Read this before touching the data model.

## Mental Model

### Specs Live on Branches

A **spec** = one feature.yaml on one branch. Same feature has many specs over time (branches), but few long-lived versions (prod, dev).

**Uniqueness:** `(team_id, repo_uri, branch_name, feature_name)` - pushing same feature on same branch updates existing spec.

**Implication:** Renaming a feature creates a new spec. Version (from feature.yaml) is separate, prevents duplicates across branches.

### Implementations Inherit

An **implementation** = a product version (prod, dev, feature-x). Implements optional parent chain via `parent_implementation_id`.

**Snapshot on create:** When creating a child impl, states and refs are copied from parent. This prevents drift - parent changes don't affect child.

**Push behavior:** Refs in push overwrite; states persist unless explicitly modified.

### Tracked Branches Link Impls to Specs

```
implementation → tracked_branches → specs (match on branch_name + feature_name)
```

Each impl tracks branches. Features available = specs on those branches.

## Data Model

### Key Tables

| Table | Uniqueness | Notes |
|-------|------------|-------|
| `specs` | `(team_id, repo_uri, branch_name, feature_name)` | Also `(team_id, feature_name, feature_version)` |
| `implementations` | `(product_id, name)` | Self-ref via `parent_implementation_id` |
| `tracked_branches` | `(implementation_id, repo_uri)` | One branch per repo per impl |
| `spec_impl_states` | `(spec_id, implementation_id)` | JSONB keyed by ACID |
| `spec_impl_refs` | `(spec_id, implementation_id)` | JSONB keyed by ACID |

### JSONB Structures

**Requirements** (in specs):
```json
{
  "FEATURE.COMPONENT.1-1": {
    "definition": "string",
    "note": "optional",
    "is_deprecated": false,
    "replaced_by": []
  }
}
```

**States** (in spec_impl_states):
```json
{
  "FEATURE.COMPONENT.1-1": {
    "status": "pending|in_progress|blocked|completed|rejected",
    "comment": "optional",
    "metadata": {},
    "updated_at": "timestamp"
  }
}
```

**Refs** (in spec_impl_refs):
```json
{
  "FEATURE.COMPONENT.1-1": [
    { "repo": "uri", "path": "file.ex", "loc": "15:3", "is_test": false }
  ]
}
```

### Key Indexes

- `(repo_uri, branch_name)` on tracked_branches → find impl tracking a branch
- `(product_id)` on specs → list specs by product
- GIN on JSONB columns → query by ACID key

### Naming Rules

- Product: `[a-zA-Z0-9_-]`, CITEXT, unique per team
- Feature: `[a-zA-Z0-9_-]`, not globally unique
- Feature version: SemVer, defaults to 1.0.0

## API (MVP)

### `/push` - Idempotent Updates

Push spec and/or refs. Creates impl if `implementation_id`/`implementation_name` provided. Must work idempotently with or without inheritance.

### `/status` - State Management

- GET by ACID → state from snapshot
- PATCH single/batch → update status, comment

## Common Queries

### Find Nearest Spec (for requirements)

1. Get tracked branches for impl
2. Match specs on `branch_name` + `feature_name`
3. If none found, recurse to parent impl
4. Depth ≤ 4 typically (prod → dev → feature → task)

Note: This finds the *spec* (requirements). States/refs are already snapshotted locally.

### Get State for ACID

Simple lookup - states are snapshotted to each impl:

```sql
SELECT states->>$1 FROM spec_impl_states
WHERE spec_id = $2 AND implementation_id = $3;
```

## Edge Cases

- **Orphaned states:** ACID removed from spec → states/refs retained for reinstatement
- **Branch collisions:** `frontend/main` ≠ `backend/main` (scoped to `repo_uri`)
- **Spec renames:** New `feature_name` = new spec; old spec + states preserved
- **Parent deletion:** `parent_implementation_id` SET NULL, child survives
- **Drift prevention:** Snapshots isolate child from parent changes post-creation

## Future

- Auto-create impls on push via git upstream detection
- Branch naming conventions (`feature/*` → inherit from dev)
- Bulk state sync between parent/child
