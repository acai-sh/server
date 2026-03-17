## Route
`/t/:team_name/f/:feature_name` -> `AcaiWeb.FeatureLive`

## Data Flow

**Initial Page Load (mount/3):**
1. Fetch team by name (`Teams.get_team_by_name!/1`)
2. Fetch specs by feature name (`Specs.get_specs_by_feature_name/2`) - FIRST CALL
3. Call `get_product_for_feature/2` which calls `Specs.get_specs_by_feature_name/2` AGAIN - DUPLICATE
4. Fetch available features for dropdown (`Specs.list_features_for_product/1`)
5. Preload product on first_spec (in `get_product_for_feature`) - FIRST PRELOAD
6. Preload product on first_spec AGAIN (in `load_feature_data`) - DUPLICATE PRELOAD
7. Fetch active implementations for specs (`Implementations.list_active_implementations_for_specs/1`)
8. Preload product association on all implementations (`Repo.preload(implementations, :product)`)
9. Batch fetch status counts (`Implementations.batch_get_spec_impl_state_counts/2`)
10. Build implementation_cards list with computed percentages (in-memory transformation)

**URL Patch Navigation (handle_params/3 -> reload_feature_data/3):**
- Repeats the ENTIRE data loading sequence above (steps 1-10)
- This happens when user selects a different feature from the dropdown

**Event Handling (handle_event/3):**
- `select_feature` event only triggers `push_patch/2` - no data loading

## Findings

### Finding 1: Duplicate Specs Query
- **Severity:** high
- **Location:** `lib/acai_web/live/feature_live.ex:19` and `lib/acai_web/live/feature_live.ex:39`
- **Evidence:** 
  - Line 19: `case Specs.get_specs_by_feature_name(team, feature_name) do`
  - Line 13: `product = get_product_for_feature(team, feature_name)`
  - Line 39 (inside get_product_for_feature): `case Specs.get_specs_by_feature_name(team, feature_name) do`
- **Risk:** redundant fetch
- **Recommendation:** Pass the specs result from mount into get_product_for_feature instead of refetching. Change `get_product_for_feature/2` to accept specs as parameter: `get_product_for_feature(team, specs)`.

### Finding 2: Duplicate Product Preload
- **Severity:** medium
- **Location:** `lib/acai_web/live/feature_live.ex:44` and `lib/acai_web/live/feature_live.ex:52`
- **Evidence:**
  - Line 44: `first_spec = List.first(specs) |> Acai.Repo.preload(:product)`
  - Line 52: `first_spec = List.first(specs) |> Acai.Repo.preload(:product)`
- **Risk:** redundant fetch
- **Recommendation:** Remove the preload from `get_product_for_feature/2` since `load_feature_data/6` already performs it. Or better, pass the already-preloaded spec from `load_feature_data` to avoid both preloads.

### Finding 3: Serialized Queries in get_specs_by_feature_name
- **Severity:** medium
- **Location:** `lib/acai/specs/specs.ex:130-156`
- **Evidence:**
  ```elixir
  def get_specs_by_feature_name(%Team{} = team, feature_name) do
    actual_feature_name =
      Repo.one(
        from s in Spec, ... limit: 1  # QUERY 1
      )
    if actual_feature_name do
      specs =
        Repo.all(
          from s in Spec, ...          # QUERY 2
        )
  ```
- **Risk:** serialized queries
- **Recommendation:** Consider using a CTE or subquery to fetch both the actual_feature_name and specs in a single round-trip. The first query only needs to get one row for the feature_name, then the second fetches all matching specs. These could be combined with a JOIN or using `fragment` with a subquery.

### Finding 4: Redundant Team Fetch on Patch Navigation
- **Severity:** low
- **Location:** `lib/acai_web/live/feature_live.ex:161`
- **Evidence:**
  - Line 161 in `reload_feature_data/3`: `team = Teams.get_team_by_name!(team_name)`
  - The team is already assigned in socket.assigns from initial mount
- **Risk:** redundant fetch
- **Recommendation:** In `reload_feature_data`, use `socket.assigns.team` instead of refetching. The team name in the URL cannot change without a full navigation.

### Finding 5: Implementation Preload Without Batch Optimization
- **Severity:** low
- **Location:** `lib/acai_web/live/feature_live.ex:64`
- **Evidence:** `implementations = Acai.Repo.preload(implementations, :product)`
- **Risk:** N+1 potential (though Ecto preload batches, this is still a separate query)
- **Recommendation:** Move the product preload into `list_active_implementations_for_specs/1` so the join happens at query time instead of separate preload query. This would change from 2 queries to 1.

### Finding 6: Excess Assigns Storage
- **Severity:** low
- **Location:** `lib/acai_web/live/feature_live.ex:122-138`
- **Evidence:**
  ```elixir
  |> assign(:team, team)
  |> assign(:feature_name, actual_feature_name)
  |> assign(:feature_description, first_spec.feature_description)
  |> assign(:product_name, first_spec.product.name)
  |> assign(:product, product)
  |> assign(:implementations_empty?, implementation_cards == [])
  |> stream(:implementations, implementation_cards)
  |> assign(:available_features, available_features)
  |> assign(:current_path, "/t/#{team.name}/f/#{actual_feature_name}")
  ```
- **Risk:** excess assigns
- **Recommendation:** 
  - `:product_name` is redundant with `product.name` - derive in template or use `@product.name`
  - `:implementations_empty?` can be derived in template with `@streams.implementations` (though streams don't expose count, consider tracking count separately)
  - `:current_path` is recomputed in `handle_params/3` anyway (line 145)

### Finding 7: Full Data Reload on Feature Change
- **Severity:** medium
- **Location:** `lib/acai_web/live/feature_live.ex:159-181`
- **Evidence:** `reload_feature_data/3` calls all the same expensive operations as initial mount
- **Risk:** redundant fetch, serialized queries
- **Recommendation:** The product and available_features only change if the feature belongs to a different product. Consider caching or only reloading when necessary. If most feature switches are within the same product, this is wasted work.

### Finding 8: Status Percentages Computed Per-Implementation
- **Severity:** low
- **Location:** `lib/acai_web/live/feature_live.ex:85-104`
- **Evidence:** Percentage calculation happens in Enum.map for each implementation card
- **Risk:** excess computation (minor)
- **Recommendation:** This is already efficient (O(n) where n=implementations). No change needed unless implementations count is very high (>1000), in which case move to JavaScript or virtualize.

## Query Checklist

- **Duplicate fetches:** YES
  - `Specs.get_specs_by_feature_name/2` called twice per request (lines 19 and 39)
  - `Repo.preload(:product)` on first_spec called twice (lines 44 and 52)
  - Team fetched again in `reload_feature_data/3` when already in assigns

- **Possible N+1s:** NO
  - Implementations are fetched with a single IN query by product_ids
  - Status counts use `batch_get_spec_impl_state_counts/2` which aggregates in one query
  - Product preload on implementations is done via Ecto preload (batches automatically)

- **Overloaded assigns:** YES
  - `:product_name` is derivable from `:product`
  - `:implementations_empty?` could be tracked as count instead of boolean
  - `:current_path` is derived and also updated in handle_params

- **Batch/consolidation opportunities:** YES
  - The two queries in `get_specs_by_feature_name/2` could be consolidated
  - Product preload could be moved into the implementations query as a JOIN
  - `get_product_for_feature` could be eliminated entirely by returning product info from `get_specs_by_feature_name`

## Suggested Next Step

1. **Eliminate duplicate specs query (Highest Impact)**
   - Modify `get_product_for_feature/2` to accept specs instead of refetching
   - This saves one database round-trip per request (saves ~10-30ms depending on DB latency)

2. **Consolidate product preload (Medium Impact)**
   - Move `:product` preload into `list_active_implementations_for_specs/1` query as JOIN
   - This reduces queries from 3 to 2 for implementations loading

3. **Avoid redundant team fetch in reload (Low Impact)**
   - Use `socket.assigns.team` in `reload_feature_data/3`
   - Minor save but straightforward fix

## Implement If Needed

**Change 1: Remove duplicate specs query**
```elixir
# In mount/3, change:
product = get_product_for_feature(team, feature_name)
# To:
product = get_product_from_specs(specs)  # new helper that doesn't query

# Remove get_product_for_feature/2 entirely
# Add:
defp get_product_from_specs([]), do: nil
defp get_product_from_specs([first_spec | _]) do
  # Preload product once here if not already loaded
  Acai.Repo.preload(first_spec, :product).product
end
```
- Expected impact: Eliminates 1 query (the specs lookup duplicate)
- Verification: Add logging or use `Ecto.DevLogger` to confirm query count reduction

**Change 2: Inline product preload into implementations query**
```elixir
# In Implementations.list_active_implementations_for_specs/1, change:
Repo.all(from i in Implementation, where: i.product_id in ^product_ids and i.is_active == true)
# To:
Repo.all(
  from i in Implementation,
    where: i.product_id in ^product_ids and i.is_active == true,
    join: p in assoc(i, :product),
    preload: [product: p]
)
```
- Expected impact: Eliminates 1 query (the separate preload call)
- Verification: Check that `Repo.preload(implementations, :product)` can be removed in FeatureLive

**Change 3: Remove redundant team fetch**
```elixir
# In reload_feature_data/3, change:
team = Teams.get_team_by_name!(team_name)
# To:
team = socket.assigns.team
```
- Expected impact: Eliminates 1 query on feature dropdown changes
- Verification: Test feature dropdown navigation still works

**Metrics to compare:**
- Before/after query count (visible in logs with `config :acai, Acai.Repo, log: :debug`)
- Before/after response time for the feature show page (can measure with browser dev tools or LiveDashboard)
