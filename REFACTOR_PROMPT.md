# Architectural Refactor: Product-Level Implementations

## Core Changes

**1. Products are now first-class entities** - New `products` table replaces derived `feature_product` strings. Products exist independently of specs and can be created before any features.

**2. Implementations span products, not features** - `implementations.spec_id` → `implementations.product_id`. An implementation (e.g., "Production") now encompasses the state of ALL features within a product.

**3. Requirement statuses stored as JSONB snapshots** - Dropped `requirement_statuses` table. New `feature_implementation_states` table with `status_snapshot` JSONB column: `{"my-feature.COMP.1": {"status": "accepted", "note": "LGTM"}}`. Enables fast inheritance (bulk copy rows) and concurrent updates across features.

**4. All implementation API routes nested under products** - `/api/v1/implementations/*` → `/api/v1/products/:product_id/implementations/*`

**5. Push endpoint requires explicit product identifier** - `POST /api/v1/push` now requires `product_id` or `product_name`. Inheritance copies all feature_implementation_states rows from parent.

**6. Implementation URLs include product** - `/t/:team/f/:feature/i/:impl` → `/t/:team/p/:product/i/:impl`

---

## Changed Specs

| Spec | Key Changes |
|------|-------------|
| `data-model` | +PRODUCTS table, +FEATURE_IMPL_STATES (JSONB), IMPLS.spec_id→product_id, SPECS.feature_product→product_id |
| `api/products` | Read-only → Full CRUD |
| `api/implementations` | URLs nested under products, +CRUD, product-scoped coverage |
| `api/impl-branches` | URLs nested under products |
| `api/impl-refs` | URLs nested under products, +feature_name filter |
| `api/impl-reqs` | → feature-states concept, JSONB merge updates |
| `api/features` | Implementations array uses product_id |
| `api/push` | +product_id/product_name required, JSONB inheritance |
| `product-view` | Query products table |
| `implementation-view` | New URL pattern, JSONB coverage |
| `feature-view` | Product-scoped implementations |
| `requirement-details` | Status from JSONB snapshot |
| `nav` | Products from table, new URL highlighting |
| `seed-data` | +PRODUCTS seeding |
| `team-settings` | Products in cascade delete warning |

---

## Refactor Order

```
Phase 1 (Foundation)
  1. data-model      ← Migrations, schemas, JSONB
  2. seed-data       ← Update seeding

Phase 2 (API)
  3. api/products    ← CRUD endpoints
  4. api/implementations  ← URL restructure, CRUD
  5. api/impl-branches   ← URL restructure
  6. api/impl-refs       ← URL restructure
  7. api/impl-reqs       ← JSONB feature-states
  8. api/features        ← Minor update
  9. api/push            ← Product ID required, JSONB inheritance

Phase 3 (UI) - Can start after #3
  10. product-view       ← Products table query
  11. implementation-view ← New URL, JSONB
  12. feature-view       ← Product-scoped
  13. requirement-details ← JSONB status
  14. nav                ← Products table, URLs
```

**Parallelization:** After #3, UI (#10-14) can run in parallel with API (#4-9).

**Critical Path:** `1 → 2 → 3 → 4 → 7 → 9`
