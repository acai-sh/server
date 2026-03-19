## Route
`/t/:team_name/p/:product_name` -> `AcaiWeb.ProductLive`

## Data Flow

### Initial Page Load (mount/3 + handle_params/3)
1. **mount/3** loads:
   - Team by name (`Teams.get_team_by_name!/1`)
   - All products for the team (`Products.list_products/2`)

2. **handle_params/3** loads:
   - Product by name (case-insensitive) via `get_product_by_name_case_insensitive/2`
   - All specs for the product (`Specs.list_specs_for_product/1`)
   - All implementations for the product (`Implementations.list_implementations/1`)
   - Filters active implementations in-memory
   - Groups specs by feature_name in-memory
   - Batch fetches completion data (`Specs.batch_get_spec_impl_completion/2`)
   - Builds `matrix_rows` in-memory (nested loops: features × implementations)

### Events/Secondary Flows
- No handle_event/3 callbacks defined; this is a read-only display route
- Navigation via product selector would trigger handle_params with new product_name

## Findings

### Finding 1: All Products Loaded on Every Request
- **Severity:** medium
- **Location:** `lib/acai_web/live/product_live.ex:18`
- **Evidence:** `products = Products.list_products(socket.assigns.current_scope, team)` fetches all team products in mount/3
- **Risk:** excess assigns
- **Impact:** For teams with many products, this loads unnecessary data even when viewing a single product
- **Recommendation:** Consider lazy-loading products only when product selector is opened, or cache product list in TeamLive and pass via session

### Finding 2: Product Fetched via Separate Case-Insensitive Query
- **Severity:** low
- **Location:** `lib/acai_web/live/product_live.ex:143-150`
- **Evidence:** Custom `get_product_by_name_case_insensitive/2` performs separate query with `fragment("lower(?)", p.name)`
- **Risk:** redundant fetch (partial - needed for case-insensitive routing)
- **Impact:** One additional query per request; necessary for case-insensitive URL matching
- **Recommendation:** Acceptable as-is; the case-insensitive lookup is required for UX. Consider database CITEXT index if performance becomes issue.

### Finding 3: Specs and Implementations Fetched Sequentially
- **Severity:** medium
- **Location:** `lib/acai_web/live/product_live.ex:59-60`
- **Evidence:** 
  ```elixir
  specs = Specs.list_specs_for_product(product)
  implementations = Implementations.list_implementations(product)
  ```
- **Risk:** serialized queries
- **Impact:** Two round-trips to database that could be consolidated
- **Recommendation:** Create a `ProductContext.load_product_matrix_data/1` that returns `{specs, implementations}` in a single transaction or concurrent queries via `Task.async`

### Finding 4: Large In-Memory Matrix Computation
- **Severity:** medium
- **Location:** `lib/acai_web/live/product_live.ex:90-127`
- **Evidence:** 
  ```elixir
  matrix_rows =
    features_by_name
    |> Enum.map(fn feature ->
      cells =
        active_implementations
        |> Enum.map(fn impl ->
          # Reduces over all specs for this feature
          feature.specs
          |> Enum.reduce({0, 0}, fn spec, {acc_completed, acc_total} ->
  ```
- **Risk:** excess assigns | computation complexity O(F × I × S) where F=features, I=implementations, S=specs per feature
- **Impact:** As products scale (many features × many implementations), this computation grows quadratically. The entire matrix is stored in assigns.
- **Recommendation:** Consider stream-based rendering for large matrices; compute cell data lazily or paginate

### Finding 5: Redundant Empty State Assigns
- **Severity:** low
- **Location:** `lib/acai_web/live/product_live.ex:129-139`
- **Evidence:** 
  ```elixir
  assign(:empty?, empty?)
  |> assign(:no_features?, features_by_name == [])
  |> assign(:no_implementations?, active_implementations == [])
  ```
- **Risk:** excess assigns
- **Impact:** Three boolean assigns derived from same data; `:empty?` is computable from other two
- **Recommendation:** Consolidate to single `@empty_state` map assign or compute in template

### Finding 6: Implementation Slug Computed Per-Cell
- **Severity:** low
- **Location:** `lib/acai_web/live/product_live.ex:115`
- **Evidence:** `implementation_slug: Implementations.implementation_slug(impl)` called for every feature row (repeated I×F times)
- **Risk:** redundant computation
- **Impact:** Same slug computed repeatedly for each implementation across all feature rows
- **Recommendation:** Pre-compute implementation slugs once and store in a map or add to implementation struct before matrix build

## Query Checklist

### Duplicate fetches: **no**
- Each entity (team, products, product, specs, implementations) fetched once per lifecycle
- No duplicate queries detected

### Possible N+1s: **no**
- `Specs.batch_get_spec_impl_completion/2` at line 83 correctly batches completion data
- Uses single query with `where: fis.feature_name in ^feature_names and fis.implementation_id in ^impl_ids`
- No per-row database queries detected in template rendering

### Overloaded assigns: **yes**
- `@products` - all team products (potentially large list)
- `@matrix_rows` - full matrix data structure (quadratic growth with features × implementations)
- `@active_implementations` - filtered subset stored separately
- Multiple boolean flags for empty states

### Batch/consolidation opportunities: **yes**
- `list_specs_for_product/1` + `list_implementations/1` could be consolidated
- Products list could be lazy-loaded or cached
- Matrix computation could be deferred or streamed

## Suggested Next Step (Ordered by Impact)

1. **Consolidate specs/implementations fetch** (medium impact, low effort)
   - Create single context function that returns both in one database round-trip
   - Reduces initial page load latency

2. **Lazy-load products list** (medium impact, medium effort)
   - Only fetch products when product selector dropdown is opened
   - Requires LiveView event handler and UI change

3. **Optimize matrix computation** (high impact for large datasets, high effort)
   - Implement stream-based rendering for matrix rows
   - Or add pagination/filtering to limit visible features/implementations

## Implement If Needed

### Change 1: Consolidate Product Data Fetching
```elixir
# In Acai.Products context
def load_product_page_data(product) do
  specs_task = Task.async(fn -> Specs.list_specs_for_product(product) end)
  impls_task = Task.async(fn -> Implementations.list_implementations(product) end)
  
  specs = Task.await(specs_task)
  implementations = Task.await(impls_task)
  
  {specs, implementations}
end
```
- **Expected impact:** Reduces sequential query time; ~50% reduction in data fetch latency
- **Verification:** Log query times before/after with `Ecto.Repo telemetry`

### Change 2: Pre-compute Implementation Slugs
```elixir
# In load_product_data/2
impl_slugs = Map.new(implementations, &{&1.id, Implementations.implementation_slug(&1)})
socket = assign(socket, :impl_slugs, impl_slugs)

# Then in matrix loop:
implementaion_slug: @impl_slugs[impl.id]
```
- **Expected impact:** Eliminates F×I redundant string operations
- **Verification:** Benchmark matrix build time with Benchee

### Change 3: Stream Matrix Rows (for large datasets)
```elixir
# Replace @matrix_rows assign with stream
socket = stream(socket, :matrix_rows, matrix_rows)

# In template:
<div id="matrix-rows" phx-update="stream">
  <tr :for={{id, row} <- @streams.matrix_rows} id={id}>
```
- **Expected impact:** Reduces memory pressure for products with 50+ features
- **Verification:** Monitor memory usage with `:erlang.memory()` before/after

## Re-review 2026-03-19

### Result: REJECTED

### What improved
- `AcaiWeb.ProductLive` now uses non-raising lookups for the team/product flow.
- Matrix rows are now streamed via `@streams.matrix_rows` with `phx-update="stream"` and `reset: true`.
- Full test suite passes: `mix test` -> 894 tests, 0 failures.

### Remaining issue
- **Consolidated loader still performs an overlapping spec fetch/build pass.**
  - `Products.load_product_page/2` fetches `specs = Acai.Specs.list_specs_for_product(product)` and passes that list into `Acai.Specs.batch_get_completion_and_availability/3`.
  - Inside `batch_get_completion_and_availability/3`, the function performs another `Repo.all(from s in Spec, ...)` to rebuild `specs_by_branch/specs_by_feature` for the same product/feature set.
  - This means the prior review issue is only partially fixed: the separate completion/availability helper paths were consolidated, but the loader still does a second overlapping spec pass instead of reusing the already-loaded `specs` list.

### Action items
- [ ] Remove the second spec query from `Acai.Specs.batch_get_completion_and_availability/3`.
- [ ] Derive `specs_by_feature` / branch-id lookup data directly from the `specs` argument already loaded by `Products.load_product_page/2`.
- [ ] Keep the shared ancestry/tracked-branch/state pass, but ensure spec lookup state is built once from the in-memory `specs` list.
- [ ] Add/adjust a focused test covering that the consolidated loader reuses the passed spec set for both completion and availability logic.

## Re-review 2026-03-19 (pass 2)

### Result: ACCEPTED

### Verified
- `Products.load_product_page/2` still loads specs once, and `Acai.Specs.batch_get_completion_and_availability/3` now derives availability data from the already-loaded `specs` list instead of issuing a second `Spec` query.
- The overlapping `Spec` fetch inside the consolidated product-page loader path has been eliminated; the shared loader now only batches ancestry, tracked-branch, and state reads.
- Matrix streaming is still correct: `ProductLive` initializes `:matrix_rows` as a stream, renders via `@streams.matrix_rows`, and resets the stream on product changes.
- Non-raising LiveView lookups are in place for the reviewed flow via `Products.get_team_by_name/1` and `Products.get_product_from_list/3`.
- Full test suite passes: `mix test` -> 894 tests, 0 failures.

### Supervisor notification
The code for `/app/docs/reviews/routes/202603_product-show.task.md` has passed review and can be merged.
