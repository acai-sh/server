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

# Ideas
Document a prune concept that also identifies when two branches mirror an identical spec (child specs can be removed)

---

plan of attack
- spec realignment of data model, remove deprecated fields, clean up refs, handle renumbering
plus full re-write of seed-data following the fully re-written spec

- QA verification of seed data, and simulation of `push` and light review of the push api code

- clean up reference concepts in UI
