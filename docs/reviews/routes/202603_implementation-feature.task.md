## Route
`/t/:team_name/i/:impl_slug/f/:feature_name` -> `AcaiWeb.ImplementationLive`

## Data Flow

### First Request (Initial Page Load)
1. `mount/3` receives params and fetches team by name (`Teams.get_team_by_name!/1`)
2. Parses slug and fetches implementation (`Implementations.get_implementation_by_slug/1`)
3. Preloads product association on implementation (`Repo.preload(implementation, :product)`)
4. Resolves canonical spec with inheritance walking (`Specs.resolve_canonical_spec/2`)
5. Preloads product and branch on spec (`Repo.preload(spec, [:product, :branch])`)
6. Gets feature impl state with inheritance (`Specs.get_feature_impl_state_with_inheritance/2`)
7. Gets aggregated refs with inheritance (`Implementations.get_aggregated_refs_with_inheritance/2`)
8. Lists tracked branches with preloaded branches (`Implementations.list_tracked_branches/1`)
9. Lists available implementations for feature (`Specs.list_implementations_for_feature/2`)
10. Lists available features for implementation (`Specs.list_features_for_implementation/2`)
11. Builds requirement rows by iterating over spec.requirements and calling `Implementations.get_refs_for_acid/2` for each
12. Conditionally fetches source implementations for inherited states/refs (2 additional queries)

### Secondary Flows (Events)
- `handle_event("sort_requirements", ...)`: Re-sorts already-loaded `@requirements` assign (no DB queries)
- `handle_event("select_implementation", ...)`: Patches URL, triggers `handle_params` which calls `reload_implementation_data` (re-runs full data load)
- `handle_event("select_feature", ...)`: Patches URL, triggers same full reload
- `handle_params`: Re-fetches all data if params changed
- Drawer open/close: No DB queries

## Findings

### Finding 1: Excess Assigns - Large Data Structures in Socket
**Severity:** medium  
**Location:** `lib/acai_web/live/implementation_live.ex:79-211` (load_implementation_data)  
**Evidence:** The following assigns are stored in the socket:
- `@requirements` - List of requirement rows with computed counts per ACID (grows with spec size)
- `@available_implementations` - Full list of implementations for dropdown
- `@available_features` - Full list of features for dropdown  
- `@aggregated_refs` - Full refs structure from all tracked branches (JSONB, potentially large)

**Risk:** excess assigns  
**Recommendation:** Consider whether `@aggregated_refs` needs to be stored in its entirety. The drawer component only needs refs for the selected ACID. Store counts at render-time and fetch specific ACID refs on-demand when drawer opens.

---

### Finding 2: Redundant Fetching - Team Fetched Twice in Some Flows
**Severity:** low  
**Location:** `lib/acai_web/live/implementation_live.ex:17` and `lib/acai_web/live/implementation_live.ex:311`  
**Evidence:** Team is fetched in `mount/3` and again in `reload_implementation_data/4` during URL patch navigation.  
**Risk:** redundant fetch  
**Recommendation:** Store team in socket assigns after initial mount; reuse in `reload_implementation_data`.

---

### Finding 3: Serialized Queries - Sequential Independent Lookups
**Severity:** high  
**Location:** `lib/acai_web/live/implementation_live.ex:79-211` (load_implementation_data)  
**Evidence:** The following queries execute sequentially but are independent:
1. `Specs.resolve_canonical_spec/2` (line 55) - walks inheritance chain
2. `Specs.get_feature_impl_state_with_inheritance/2` (line 101) - walks inheritance chain again
3. `Implementations.get_aggregated_refs_with_inheritance/2` (line 108) - walks inheritance chain a third time
4. `Implementations.list_tracked_branches/1` (line 113)
5. `Specs.list_implementations_for_feature/2` (line 118)
6. `Specs.list_features_for_implementation/2` (line 123)

Each inheritance walk makes multiple DB calls (get implementation, get tracked branch IDs, query specs/refs).

**Risk:** serialized queries  
**Recommendation:** Create a consolidated context function `ImplementationViewData.load/team_id, implementation_id, feature_name)` that fetches all required data in a single transaction or uses `Task.async_stream` for the independent queries.

---

### Finding 4: N+1 Risk - Per-Item Helper Calls in Template
**Severity:** medium  
**Location:** `lib/acai_web/live/implementation_live.ex:579-583` (title_picker template)  
**Evidence:** Dropdown iteration calls `Implementations.implementation_slug/1` for each implementation to generate comparison values:
```elixir
allowed_impl_slugs = MapSet.new(available_implementations, &Implementations.implementation_slug/1)
```
While `implementation_slug/1` is a pure function (string manipulation only), this pattern appears in both the template and the event handler.

**Risk:** other  
**Recommendation:** Precompute slugs when loading `available_implementations` and store as a map or include slug in the struct if frequently used.

---

### Finding 5: N+1 Risk - Per-Requirement Ref Counting
**Severity:** high  
**Location:** `lib/acai_web/live/implementation_live.ex:128-161`  
**Evidence:** For each requirement, the code calls:
```elixir
acid_refs = Implementations.get_refs_for_acid(aggregated_refs, acid)
```
This iterates over `@aggregated_refs` (list of {branch, refs_map} tuples) for every requirement. For N requirements and M branches, this is O(N*M).

**Risk:** N+1  
**Recommendation:** Build a lookup map once: `Map.new(requirements, fn req -> {req.acid, calculate_refs_counts(req.acid, aggregated_refs)} end)` instead of nested iteration.

---

### Finding 6: Duplicate Inheritance Walking
**Severity:** high  
**Location:** `lib/acai_web/live/implementation_live.ex:101` and `lib/acai_web/live/implementation_live.ex:108`  
**Evidence:** Both `get_feature_impl_state_with_inheritance` and `get_aggregated_refs_with_inheritance` walk the same parent implementation chain independently. Each walks from current implementation -> parent -> grandparent etc., making separate DB queries for the same implementation hierarchy.

**Risk:** redundant fetch, serialized queries  
**Recommendation:** Walk the inheritance chain once, collecting all implementation IDs, then batch-fetch states and refs for the entire chain in single queries.

---

### Finding 7: Template-Level Query in target_spec_card
**Severity:** medium  
**Location:** `lib/acai_web/live/implementation_live.ex:671-685`  
**Evidence:** The template conditionally fetches a source implementation:
```elixir
<% source_impl = Acai.Implementations.get_implementation(@spec_source.source_implementation_id) %>
```
This executes a DB query during render phase when the inherited badge is clicked.

**Risk:** N+1  
**Recommendation:** Preload `source_impl` in `load_implementation_data` when `@spec_inherited` is true.

---

### Finding 8: Inefficient Sorting on Large Lists
**Severity:** low  
**Location:** `lib/acai_web/live/implementation_live.ex:229-236`  
**Evidence:** `sort_requirements/3` uses `Enum.sort_by` which creates sort keys for every element on every sort event.  
**Risk:** other  
**Recommendation:** For large requirement lists, consider storing pre-sorted indices or using LiveView streams with client-side sorting.

---

### Finding 9: Full Data Reload on URL Patch
**Severity:** medium  
**Location:** `lib/acai_web/live/implementation_live.ex:310-334`  
**Evidence:** When user selects different implementation or feature from dropdown, `reload_implementation_data` re-fetches everything including:
- Team (already known)
- Implementation (changed, needed)
- Product (likely same)
- Spec (may be same)
- Tracked branches (may be same)
- Available implementations/features (likely same set)

**Risk:** redundant fetch  
**Recommendation:** Cache `available_implementations` and `available_features` in socket if product hasn't changed. These are used for dropdowns and rarely change between navigation.

---

## Query Checklist

- **Duplicate fetches:** YES
  - Team fetched in both `mount` and `reload_implementation_data`
  - Implementation hierarchy walked 3 times independently (spec resolution, states, refs)
  - `source_impl` fetched lazily in template

- **Possible N+1s:** YES
  - `get_refs_for_acid` called per requirement (O(N*M) iteration)
  - Template calls `get_implementation` during render for inherited badge

- **Overloaded assigns:** YES
  - `@aggregated_refs` stores full JSONB structure for all branches/ACIDs
  - `@available_implementations` and `@available_features` store full lists for dropdowns
  - `@requirements` stores derived counts that could be computed at query time

- **Batch/consolidation opportunities:** YES
  - Inheritance chain walking (3 separate walks can become 1)
  - Independent queries in `load_implementation_data` can be parallelized
  - Source implementation preloading can be conditional in initial load

## Suggested Next Step

1. **Consolidate inheritance walking** (highest impact): Create a single context function that walks the implementation parent chain once and returns `{spec_with_source, states_with_source, refs_with_source}` in one pass. This eliminates the triple-walking of the same hierarchy.

2. **Optimize requirement row building** (medium impact): Build an ACID-to-refs lookup map once before the requirement iteration, eliminating O(N*M) nested iteration.

3. **Remove template-level query** (quick win): Preload the spec source implementation in `load_implementation_data` when `spec_inherited` is true.

## Implement If Needed

### Change 1: Consolidate Inheritance Walking
**Implementation:** Create `Acai.Specs.resolve_canonical_spec_with_data/2` that returns `{spec, spec_source, states, states_source, refs, refs_source}` in a single parent-chain walk.

**Expected Impact:** Reduces DB queries from ~6-10 (depending on chain depth) to ~3-4 per request.

**Verification:** 
```bash
# Before/after query count comparison
mix test test/acai_web/live/implementation_live_test.exs --trace
# Check logs for query count reduction
```

### Change 2: Precompute ACID Refs Lookup Map
**Implementation:** In `load_implementation_data`, before building requirement_rows:
```elixir
acid_refs_map = 
  for req <- requirements, into: %{} do
    {req.acid, Implementations.get_refs_for_acid(aggregated_refs, req.acid)}
  end
```
Then reference `acid_refs_map[acid]` in the Enum.map.

**Expected Impact:** Eliminates O(N*M) iteration, becomes O(N+M).

**Verification:** Add timing to `build_requirement_rows_from_spec` and test with specs containing 50+ requirements.

### Change 3: Lazy Load Drawer Data
**Implementation:** Remove `@aggregated_refs` from socket assigns. Pass only `spec`, `implementation`, and `acid` to drawer. Have drawer component call a context function to fetch refs for just that ACID when opened.

**Expected Impact:** Reduces initial payload size by size of `aggregated_refs` JSONB structure.

**Verification:** Compare socket state size before/after using `:erlang.term_to_binary` byte_size on assigns.
