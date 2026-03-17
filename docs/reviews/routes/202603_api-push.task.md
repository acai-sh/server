## Route
`/api/v1/push` -> `AcaiWeb.Api.PushController`

## Data Flow

### Initial Request Load (POST /api/v1/push)
1. **Authentication Layer** (`BearerAuth` plug at `/app/lib/acai_web/api/plugs/bearer_auth.ex:27-58`):
   - Extracts Bearer token from Authorization header
   - Calls `Teams.authenticate_api_token/1` which performs one query to fetch token by hash, then preloads team
   - Assigns `current_token`, `current_team`, `current_team_id` to conn

2. **Controller** (`PushController.create/2` at `/app/lib/acai_web/controllers/api/push_controller.ex:89-131`):
   - Extracts token from conn.assigns
   - Validates required fields (repo_uri, branch_name, commit_hash) - in-memory only
   - Delegates to `Push.execute/2`

3. **Service Layer** (`Push.execute/2` at `/app/lib/acai/services/push.ex:33-39`):
   - Performs scope checking (4 separate `token_has_scope?/2` calls)
   - Wraps all work in `Repo.run_transaction/1`

4. **Inside Transaction** (`do_push_internal/2` at `/app/lib/acai/services/push.ex:81-176`):
   - Step 1: Gets or creates branch via `get_or_create_branch/1` (1 query to check, 1 insert/update)
   - Step 2: If specs present, resolves product/implementation via `handle_specs_push/4` which queries existing trackings with preloads
   - Step 3: Writes specs via `write_specs/3` (N queries: 1 lookup per spec + 1 insert/update per spec)
   - Step 4: Writes refs via `write_refs/3` (N queries: 1-2 lookups per feature + 1 upsert per feature)
   - Step 5: Writes states via `write_states/3` (N queries: 1-2 lookups per feature + potential parent lookup + 1 upsert per feature)

### No Secondary Flows
This is a controller action (not LiveView), so there are no event-driven secondary data loads. All work happens in the single request/response cycle.

## Findings

### Finding 1: N+1 Query Pattern in Spec Writing
- **Severity:** `high`
- **Location:** `/app/lib/acai/services/push.ex:515-569` (write_specs function)
- **Evidence:** 
  ```elixir
  Enum.reduce(specs, {0, 0}, fn spec_input, {created, updated} ->
    # ... prepare spec_attrs ...
    existing_spec =
      Repo.one(
        from s in Spec,
          where: s.branch_id == ^branch.id and s.feature_name == ^feature_name
      )
    # ... insert or update ...
  end)
  ```
- **Risk:** N+1 query - For each spec in the request, performs: (1) lookup query for existing spec, (2) insert or update. With 100 specs, this is 100 SELECT queries + 100 INSERT/UPDATE queries within the transaction.
- **Recommendation:** Use `Repo.insert_all/3` with `on_conflict` for bulk upsert, or batch fetch all existing specs first with a single query using `where: s.feature_name in ^feature_names`, then perform in-memory diff before writing.

### Finding 2: N+1 Query Pattern in Reference Writing
- **Severity:** `high`
- **Location:** `/app/lib/acai/services/push.ex:593-652` (write_refs function)
- **Evidence:**
  ```elixir
  Enum.each(refs_by_feature, fn {feature_name, acid_refs} ->
    # First query to get existing
    existing = case Repo.one(from fbr in FeatureBranchRef, where: fbr.branch_id == ^branch.id and fbr.feature_name == ^feature_name) ...
    # ... later another query for upsert
    case Repo.one(from fbr in FeatureBranchRef, where: fbr.branch_id == ^branch.id and fbr.feature_name == ^feature_name) ...
  end)
  ```
- **Risk:** For each unique feature in refs, performs 2 SELECT queries (one for merge lookup, one for upsert lookup - potentially identical) + 1 INSERT/UPDATE. With 50 features, this is 100+ SELECT queries.
- **Recommendation:** Batch fetch all existing FeatureBranchRefs in a single query using `where: fbr.feature_name in ^feature_names`, store in a map, then iterate and upsert using Ecto's `insert_all` with `on_conflict: :replace_all`.

### Finding 3: N+1 Query Pattern in State Writing with Parent Lookup
- **Severity:** `high`
- **Location:** `/app/lib/acai/services/push.ex:657-725` (write_states function)
- **Evidence:**
  ```elixir
  Enum.each(states_by_feature, fn {feature_name, acid_states} ->
    existing_state = Repo.one(from fis in FeatureImplState, where: fis.implementation_id == ^implementation.id and fis.feature_name == ^feature_name)
    
    # If first write with parent, ANOTHER query:
    parent_states = case Repo.one(from fis in FeatureImplState, where: fis.implementation_id == ^implementation.parent_implementation_id and fis.feature_name == ^feature_name) ...
  end)
  ```
- **Risk:** For each unique feature in states, performs 1-2 SELECT queries + 1 INSERT/UPDATE. If inheriting from parent implementation, queries parent state separately for EACH feature. With 30 features and a parent implementation, this is 60+ SELECT queries.
- **Recommendation:** Batch fetch all existing states for the implementation in one query, batch fetch all parent states in one query (if parent exists), store in maps keyed by feature_name, then process in memory.

### Finding 4: Sequential Independent Lookups Instead of Batch Fetch
- **Severity:** `medium`
- **Location:** `/app/lib/acai/services/push.ex:296-434` (handle_untracked_branch_push function)
- **Evidence:**
  ```elixir
  # Query 1: Product lookup
  case Repo.one(from p in Product, where: p.team_id == ^team_id and p.name == ^product_name)
  
  # Query 2: Target implementation lookup (if target_impl_name provided)
  case Repo.one(from i in Implementation, where: i.product_id == ^product.id and i.name == ^target_impl_name and i.team_id == ^team_id)
  
  # Query 3: Existing repo tracking check
  Repo.one(from tb in TrackedBranch, join: b in Branch, where: tb.implementation_id == ^impl.id and b.repo_uri == ^branch.repo_uri)
  
  # Query 4: Parent implementation lookup
  case Repo.one(from i in Implementation, where: i.product_id == ^product.id and i.name == ^parent_impl_name and i.team_id == ^team_id)
  
  # Query 5: Existing implementation name collision check
  Repo.one(from i in Implementation, where: i.product_id == ^product.id and i.name == ^impl_name and i.team_id == ^team_id)
  
  # Query 6: Existing trackings check
  Repo.all(from tb in TrackedBranch, where: tb.branch_id == ^branch.id)
  ```
- **Risk:** 6 sequential queries where some could be consolidated. For example, target_impl and parent_impl lookups could be batched if both names are provided.
- **Recommendation:** If both `target_impl_name` and `parent_impl_name` are provided, fetch both implementations in a single query using `where: i.name in ^[target_impl_name, parent_impl_name]`.

### Finding 5: Duplicate Product Name Extraction Logic
- **Severity:** `low`
- **Location:** `/app/lib/acai/services/push.ex:184-191` and `273-280`
- **Evidence:** Same extraction logic appears twice:
  ```elixir
  specs
  |> Enum.map(fn spec ->
    feature = spec[:feature] || spec["feature"] || %{}
    feature[:product] || feature["product"]
  end)
  |> Enum.reject(&is_nil/1)
  |> Enum.uniq()
  ```
- **Risk:** Code duplication; minor CPU overhead for large spec lists (traverses specs twice)
- **Recommendation:** Extract to a shared private function like `extract_product_names_from_specs/1`.

### Finding 6: In-Memory Key Conversion Overhead
- **Severity:** `low`
- **Location:** Throughout `/app/lib/acai/services/push.ex`
- **Evidence:** Pattern repeated 20+ times:
  ```elixir
  specs = params[:specs] || params["specs"] || []
  feature = spec[:feature] || spec["feature"] || %{}
  feature_name = feature[:name] || feature["name"]
  ```
- **Risk:** Defensive atom/string key access adds CPU overhead for each parameter access. With large payloads, this adds up.
- **Recommendation:** Normalize params once at the start of `execute/2` using something like `Map.new(params, fn {k, v} -> {to_string(k), v} end)` or use pattern matching on normalized maps.

### Finding 7: Multiple Scope Checks as Separate Operations
- **Severity:** `low`
- **Location:** `/app/lib/acai/services/push.ex:49-52`
- **Evidence:**
  ```elixir
  has_refs_write = Acai.Teams.token_has_scope?(token, "refs:write")
  has_states_write = Acai.Teams.token_has_scope?(token, "states:write")
  has_specs_write = Acai.Teams.token_has_scope?(token, "specs:write")
  has_impls_write = Acai.Teams.token_has_scope?(token, "impls:write")
  ```
  Each call does `required_scope in (token.scopes || [])` - O(N) list membership checks.
- **Risk:** Minor CPU overhead; 4 list traversals when 1 would suffice.
- **Recommendation:** Convert scopes to a MapSet once: `scope_set = MapSet.new(token.scopes || [])`, then use `MapSet.member?(scope_set, "refs:write")`.

### Finding 8: Feature Name Extracted Multiple Times Per ACID
- **Severity:** `medium`
- **Location:** `/app/lib/acai/services/push.ex:599-601`, `662-664`, `728-735`
- **Evidence:** `extract_feature_name_from_acid/1` is called via `Enum.group_by` for refs and states processing. The same ACIDs are processed again in other contexts.
- **Risk:** String splitting operation happens multiple times on the same data. With 1000 ACIDs, this is 1000+ string splits.
- **Recommendation:** When first processing the push request, pre-compute a mapping of `acid -> feature_name` and pass it through to the write functions, or store feature_name in the grouped data structure.

## Query Checklist

- **Duplicate fetches:** yes
  - In `write_refs/3`, the same `FeatureBranchRef` is queried twice (lines 611-617 and 631-634) for the same feature within the same iteration
  - In `handle_specs_push/4`, existing trackings are queried (line 204-209), then `handle_tracked_branch_push/4` receives preloaded implementations, but later `resolve_existing_implementation/4` queries them again (lines 464-469) if no specs are provided

- **Possible N+1s:** yes
  - `write_specs/3`: 1 query per spec (lookup) + 1 write per spec
  - `write_refs/3`: 2 queries per feature + 1 write per feature
  - `write_states/3`: 1-2 queries per feature + 1 write per feature (extra query if parent inheritance needed)

- **Overloaded assigns:** no (not applicable for controller routes)
  - This is a controller, not LiveView, so there is no socket with assigns
  - The response is a minimal JSON payload (lines 164-174 in push.ex)

- **Batch/consolidation opportunities:** yes
  - Spec writes: Can use `Repo.insert_all` with `on_conflict`
  - Ref writes: Can batch fetch all existing records first
  - State writes: Can batch fetch all existing + parent states first
  - Implementation lookups: Can batch fetch target + parent in one query

## Suggested Next Step

### 1. Batch Spec Upserts (Highest Impact)
Refactor `write_specs/3` to:
1. Extract all feature_names from specs input
2. Single query: `Repo.all(from s in Spec, where: s.branch_id == ^branch.id and s.feature_name in ^feature_names)`
3. Build map of existing specs keyed by feature_name
4. Partition specs into `to_insert` and `to_update` lists
5. Use `Repo.insert_all(Spec, to_insert)` and `Repo.update_all` with a case expression or individual updates for the updates (or keep individual updates if count is small)

Expected impact: For 50 specs, reduces from 50 SELECT + 50 INSERT/UPDATE queries to 1 SELECT + 1-2 batch writes.

### 2. Batch Ref and State Writes (High Impact)
Apply same pattern to `write_refs/3` and `write_states/3`:
1. Extract all feature_names from input
2. Single query to fetch all existing records
3. For states with parent: single query to fetch all parent states
4. Process in memory, then batch insert/update

Expected impact: Similar reduction in query count for refs and states.

### 3. Consolidate Implementation Lookups (Medium Impact)
In `handle_untracked_branch_push/6`, if both `target_impl_name` and `parent_impl_name` are provided:
1. Single query: `Repo.all(from i in Implementation, where: i.product_id == ^product.id and i.name in ^[target_impl_name, parent_impl_name])`
2. Pattern match results to identify which is which

Expected impact: Saves 1 query when both parameters are provided (common case for inheritance workflows).

## Implement If Needed

### Change 1: Batch Spec Processing
**Location:** `/app/lib/acai/services/push.ex:515-569`

**Current code:**
```elixir
Enum.reduce(specs, {0, 0}, fn spec_input, {created, updated} ->
  existing_spec = Repo.one(from s in Spec, where: s.branch_id == ^branch.id and s.feature_name == ^feature_name)
  # insert or update
end)
```

**Refactored approach:**
```elixir
# 1. Collect all feature names
feature_names = Enum.map(specs, &get_feature_name/1)

# 2. Batch fetch existing specs
existing_specs = 
  Repo.all(from s in Spec, where: s.branch_id == ^branch.id and s.feature_name in ^feature_names)
  |> Map.new(fn s -> {s.feature_name, s} end)

# 3. Partition and batch process
{to_insert, to_update} = Enum.split_with(specs, fn spec ->
  not Map.has_key?(existing_specs, get_feature_name(spec))
end)

# 4. Bulk insert new specs
inserted_count = length(to_insert)
if inserted_count > 0 do
  now = DateTime.utc_now(:second)
  insert_attrs = Enum.map(to_insert, fn spec -> 
    # build attrs map including timestamps
  end)
  Repo.insert_all(Spec, insert_attrs)
end

# 5. Update existing (may need individual updates for changeset validation)
updated_count = length(to_update)
Enum.each(to_update, fn spec_input ->
  feature_name = get_feature_name(spec_input)
  existing = Map.get(existing_specs, feature_name)
  # perform update with changeset
end)
```

**Expected impact:** Reduces query count from O(N) to O(1) for spec lookups; reduces transaction hold time significantly for large pushes.

**Verification:** 
```bash
# Add logging or telemetry around transaction duration
mix test test/acai/services/push_test.exs
# Compare Ecto query logs before/after for large spec pushes
```

### Change 2: Normalize Params at Entry
**Location:** `/app/lib/acai/services/push.ex:33-40`

**Current code:**
```elixir
def execute(%AccessToken{} = token, params) do
  with :ok <- check_scopes(token, params) do
    Repo.run_transaction(fn -> do_push(token, params) end)
  end
end
```

**Refactored approach:**
```elixir
def execute(%AccessToken{} = token, params) do
  params = normalize_params(params)
  with :ok <- check_scopes(token, params) do
    Repo.run_transaction(fn -> do_push(token, params) end)
  end
end

defp normalize_params(params) when is_map(params) do
  Map.new(params, fn {k, v} -> 
    {to_string(k), if(is_map(v), do: normalize_params(v), else: v)}
  end)
end
```

Then remove all `params[:key] || params["key"]` patterns and use `params["key"]` directly.

**Expected impact:** Reduces CPU overhead for key access; cleaner code.

**Verification:**
```bash
mix test test/acai/services/push_test.exs
# All existing tests should pass without modification if normalization is correct
```

### Change 3: Scope Checking Optimization
**Location:** `/app/lib/acai/services/push.ex:43-71`

**Refactored approach:**
```elixir
defp check_scopes(token, params) do
  specs = params["specs"] || []
  refs = params["references"]
  states = params["states"]
  has_specs = specs != []
  
  scope_set = MapSet.new(token.scopes || [])
  
  cond do
    has_specs and not MapSet.member?(scope_set, "specs:write") ->
      {:error, "Token missing required scope: specs:write"}
    # ... other checks ...
  end
end
```

**Expected impact:** Minor CPU reduction; more readable scope checking.

**Verification:**
```bash
mix test test/acai_web/api/push_controller_test.exs
```
