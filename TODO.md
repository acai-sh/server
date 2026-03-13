# Decisions made

* [x] Implementation names are product-scoped (not team-unique). `target_impl_name` and `parent_impl_name` resolve within the product derived from pushed specs. No `--product` flag needed.
* [x] Refs are stored per branch (`feature_branch_refs`), not per implementation. Dashboard aggregates refs across tracked branches.
* [x] Implementation creation requires specs. Refs-only pushes to untracked branches are fine (refs land on the branch). States-only pushes to untracked branches are rejected.
* [x] Multi-product push is always rejected. CLI splits by product client-side.
* [x] No auto-inheritance. Parent must be explicitly specified via `parent_impl_name` at creation time only.
* [x] Version uniqueness constraint `(product_id, feature_name, feature_version)` dropped. Version is metadata, not identity. Spec identity is `(branch_id, feature_name)`.

# Specs revised

* [x] `push.feature.yaml` — canonical push endpoint spec (draft)
* [x] `data-model.feature.yaml` — deprecated FEATURE_IMPL_REFS, added FEATURE_BRANCH_REFS, deprecated SPECS.15 (version uniqueness), deprecated IMPL_CREATION.3-5 (auto-inheritance), updated INHERITANCE for branch-scoped refs
* [x] `feature-impl-view.feature.yaml` — updated prerequisites, DRAWER, and INHERITANCE for feature_branch_refs

# Open questions

* [ ] acai-ignore line to deal with ACID clashes? Or a configurable prefix to decrease the likelihood?
* [ ] Add max length requirements to core (feature names, impl names, etc)
* [ ] Max payload size for push endpoint?
* [ ] Review inheritance queries for performance — worst case depth is 3-4 levels
* [ ] What if I want to clear my applied states and revert back to inheritance?
* [ ] Need a way to manage branch linking in the UI
* [ ] Tidy spec voice — use "user" vs first person consistently?
* [ ] feature.yaml draft mode — if draft: true, safe to renumber ACIDs. Default draft: false. Warn if draft but ACIDs are detected in codebase.

# Ref query model (for dashboard)

When querying refs for a given feature + implementation:
1. Start with known impl_id and feature_name
2. Find tracked branch_ids for that implementation
3. Query `feature_branch_refs` where branch_id matches and feature_name matches
4. If none found, repeat for impl.parent_implementation_id (inheritance walk)

This works even when 2 products share a feature name (e.g. `auth`) and both track the same branch — refs are keyed on feature + branch, and the query always starts from a specific implementation which belongs to one product.

# Ordered work plan

### 1. Revise database migrations (pre-prod, edit in place)
- Drop unique index `(product_id, feature_name, feature_version)` on `specs`
- Rename `feature_impl_refs` table to `feature_branch_refs`
- Change `feature_branch_refs` FK from `implementation_id` to `branch_id`
- Change unique constraint on `feature_branch_refs` from `(implementation_id, feature_name)` to `(branch_id, feature_name)`
- Update indexes on `feature_branch_refs` accordingly (branch_id index, GIN on refs)
- Drop `agent` column from `feature_branch_refs` (deprecated, deferred post-MVP)
- Add `team_id` FK (non-nullable) to `branches` table
- Change unique constraint on `branches` from `(repo_uri, branch_name)` to `(team_id, repo_uri, branch_name)`
- Drop old index on `(repo_uri, branch_name)` — new unique constraint covers lookups
- Verify `implementations` unique constraint is `(product_id, name)` — already correct, no change needed

### 2. Update Ecto schemas and context modules
- Create `Acai.Specs.FeatureBranchRef` schema (replacing `FeatureImplRef`)
- Update `Acai.Specs` context: rename ref functions to use branch_id instead of implementation_id
- Update `Acai.Specs` ref inheritance queries to walk tracked_branches → branch_ids → feature_branch_refs
- Update `Acai.Implementations` if any ref-related logic exists there
- Remove or update legacy `spec_impl_ref` wrapper functions

### 3. Fix frontend LiveViews and queries
- Update `ImplementationLive` and `ProductLive` to aggregate refs via tracked branches
- Update `FeatureLive` if it displays ref data
- Update any nav or dashboard components that reference `feature_impl_refs`
- Verify feature-impl-view still renders correctly with branch-scoped refs

### 4. Fix and re-run tests
- Update ref-related test fixtures (`spec_impl_ref_fixture` → `feature_branch_ref_fixture`)
- Update `feature_impl_ref_test.exs` → `feature_branch_ref_test.exs`
- Update `specs_test.exs` ref tests
- Run full suite, fix breakage

### 5. Ship API core (per core.feature.yaml)
- API pipeline, OpenApiSpex setup, Bearer token auth plug
- FallbackController for unified error responses
- Token validation plug (scope checking, expiry, revocation)
- Base route structure under `/api/v1`

### 6. Ship push endpoint (per push.feature.yaml)
- Push controller + OpenApiSpex schema
- Push service module orchestrating the transaction:
    - Branch get-or-create
    - Implementation resolution (existing / new / link)
    - Spec insert-or-update
    - Ref writes (to branch)
    - State writes (to implementation, with parent snapshot on first push)
- Validation (single product, impl name resolution, product matching)
- Error responses with helpful messages
- Full test coverage per spec ACIDs
