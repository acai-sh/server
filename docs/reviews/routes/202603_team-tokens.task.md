## Route
`/t/:team_name/tokens` -> `AcaiWeb.TeamTokensLive`

## Data Flow

### Initial Page Load (mount/3)
1. **Team lookup**: `Teams.get_team_by_name!(team_name)` - fetches team by name
2. **Members lookup**: `Teams.list_team_members(team)` - fetches all team members with `:user` preloaded
3. **Active tokens**: `Teams.list_team_tokens(team)` - fetches non-revoked, non-expired tokens with `:user` preloaded
4. **Inactive tokens**: `Teams.list_inactive_team_tokens(team)` - fetches revoked/expired tokens with `:user` preloaded
5. **Permission check**: `Permissions.has_permission?/2` - pure function, no DB query
6. **Timezone offset**: Extracted from connect_params (client-side)

### Layout Component Queries (NavLive.update/2)
These run in parallel to the LiveView mount via the shared layout:
1. **Teams list**: `Teams.list_teams(current_scope)` - fetches all teams user belongs to
2. **Products data**: `Specs.list_specs_grouped_by_product(team)` - fetches all specs for team with product preload, then groups by product name

### Event Handlers
- **open_create_modal**: No DB queries (form initialization only)
- **validate**: `Teams.change_access_token/3` - changeset only, no DB
- **create_token**: 
  - `Teams.generate_token/4` - inserts token, preloads user
  - `Teams.valid_token?/1` - pure function check
  - May call `stream_insert` for active or inactive tokens
- **open_revoke_modal**: `Teams.get_access_token!(token_id)` - single token lookup
- **confirm_revoke**:
  - `Teams.revoke_token/1` - updates token
  - `Repo.preload(revoked_token, :user)` - explicit preload
  - `Teams.list_team_tokens(team)` - **REDUNDANT**: refetches all tokens just to check empty state

## Findings

### Finding 1: Serialized Queries in Mount
- **Severity**: medium
- **Location**: `lib/acai_web/live/team_tokens_live.ex:8-58`
- **Evidence**: Four sequential calls to Teams context: `get_team_by_name!`, `list_team_members`, `list_team_tokens`, `list_inactive_team_tokens`
- **Risk**: serialized queries
- **Recommendation**: The team, members, and tokens queries are independent and could be consolidated into a single context function that uses `Repo.transaction` with `async: true` or Ecto's `preload` to parallelize. However, since all queries are indexed and likely fast for typical team sizes, this is medium severity.

### Finding 2: Redundant Full Table Scan on Revoke
- **Severity**: medium
- **Location**: `lib/acai_web/live/team_tokens_live.ex:183`
- **Evidence**: `assign(:tokens_empty?, Teams.list_team_tokens(socket.assigns.team) == [])`
- **Risk**: redundant fetch
- **Recommendation**: Instead of refetching all tokens, track the empty state locally. The socket already knows if the stream was empty before deletion via `stream_delete`. Use `Enum.empty?(@streams.tokens)` or maintain a count assign that decrements on revoke.

### Finding 3: Double User Preload in generate_token
- **Severity**: low
- **Location**: `lib/acai/teams/teams.ex:291-293`
- **Evidence**: After `create_access_token`, calls `Repo.preload(token, :user)` then returns with `raw_token` attached
- **Risk**: redundant fetch
- **Recommendation**: The token was just created with `user_id` set - the user association is not preloaded. This is actually correct behavior, but could be optimized by passing the current_user directly into the result struct instead of querying again.

### Finding 4: Unrelated Expensive Query in Layout
- **Severity**: medium
- **Location**: `lib/acai_web/live/components/nav_live.ex:21`
- **Evidence**: `Specs.list_specs_grouped_by_product(team)` loads all specs with product preloads for navigation, even on the tokens page where this data is not displayed in the main content
- **Risk**: excess assigns | serialized queries
- **Recommendation**: The NavLive component loads product/spec data for the sidebar navigation on every team-scoped page. On the tokens page, this data is only used for sidebar display but could be large for teams with many specs. Consider:
1. Lazy-loading the product list via `push_event` after mount
2. Caching the grouped specs in an ETS table or process cache since they change infrequently
3. Using LiveView streams for the navigation products list if it grows large

### Finding 5: Missing Stream for Large Collections
- **Severity**: low
- **Location**: `lib/acai_web/live/team_tokens_live.ex:40-42`
- **Evidence**: Both `tokens` and `inactive_tokens` are stored as streams (good), but the inactive tokens may grow unbounded over time
- **Risk**: excess assigns
- **Recommendation**: The inactive tokens stream could accumulate thousands of revoked/expired tokens over time. Consider:
1. Limiting inactive tokens query to last N (e.g., 100 most recent)
2. Adding pagination or "load more" for inactive tokens
3. Archiving very old inactive tokens to a separate table

### Finding 6: NavLive find_product_for_feature Query
- **Severity**: low
- **Location**: `lib/acai_web/live/components/nav_live.ex:74,83,91-95`
- **Evidence**: `find_product_for_feature/2` calls `Specs.get_spec_by_feature_name/2` which does a `Repo.all` with limit 1
- **Risk**: N+1 potential
- **Recommendation**: This function is called in `parse_active_from_path` when the URL contains a feature path. On the tokens page (`/t/:team_name/tokens`), the path has no feature, so this is not triggered. Low severity since it doesn't affect this route directly, but worth noting for other routes.

## Query Checklist

- **Duplicate fetches**: **yes**
  - `Teams.list_team_tokens/1` is called twice: once in mount and once in confirm_revoke handler (line 183)
  
- **Possible N+1s**: **no**
  - All associations are properly preloaded in the main queries
  - The `token.user.email` access in the template is safe because `:user` is preloaded in both `list_team_tokens` and `list_inactive_team_tokens`
  
- **Overloaded assigns**: **yes**
  - `products_data` from NavLive loads all specs/products for the sidebar even on the tokens page
  - The inactive tokens stream can grow unbounded over time
  
- **Batch/consolidation opportunities**: **yes**
  - Team, members, and both token lists could potentially be fetched in a single context call using `Repo.async_stream` or batched queries
  - The `list_team_tokens` and `list_inactive_team_tokens` queries are mutually exclusive (a token is either active or inactive) - they could be combined into one query that returns both lists

## Suggested Next Step

1. **Eliminate redundant query in confirm_revoke** (high impact, easy fix): Replace the `Teams.list_team_tokens(socket.assigns.team) == []` check with a local state update that decrements a counter or checks stream emptiness without querying.

2. **Add limit to inactive tokens** (medium impact, easy fix): Modify `list_inactive_team_tokens` to accept a limit parameter (default 100) to prevent unbounded growth of the inactive tokens stream.

3. **Consolidate token queries** (medium impact, medium effort): Combine `list_team_tokens` and `list_inactive_team_tokens` into a single `list_tokens_by_status/1` function that returns `{active, inactive}` in one database round-trip using a single query with partitioning.

## Implement If Needed

### Change 1: Remove redundant query in confirm_revoke
**File**: `lib/acai_web/live/team_tokens_live.ex:183`
**Change**: Replace `assign(:tokens_empty?, Teams.list_team_tokens(socket.assigns.team) == [])` with logic that tracks count locally

**Example implementation**:
```elixir
# In mount, add a count assign:
|> assign(:active_token_count, length(tokens))

# In confirm_revoke, decrement instead of querying:
|> assign(:tokens_empty?, socket.assigns.active_token_count - 1 <= 0)
|> assign(:active_token_count, socket.assigns.active_token_count - 1)
```

**Expected impact**: Removes 1 query per token revocation (eliminates ~10-20ms per revoke operation)

**Verification**: Run `mix test test/acai_web/live/team_tokens_live_test.exs` and verify the "confirming revocation transfers the token" test still passes.

---

### Change 2: Limit inactive tokens query
**File**: `lib/acai/teams/teams.ex:237-249`
**Change**: Add limit parameter to prevent unbounded growth

**Example implementation**:
```elixir
def list_inactive_team_tokens(%Team{} = team, limit \\ 100) do
  now = DateTime.utc_now()
  
  Repo.all(
    from t in AccessToken,
      where:
        t.team_id == ^team.id and
          (not is_nil(t.revoked_at) or (not is_nil(t.expires_at) and t.expires_at <= ^now)),
      order_by: [desc: coalesce(t.revoked_at, t.expires_at)],
      limit: ^limit,
      preload: [:user]
  )
end
```

**Expected impact**: Caps memory usage and render time for teams with thousands of inactive tokens

**Verification**: Add a test that creates 150 inactive tokens and verifies only 100 are returned.

---

### Change 3: Consolidate active/inactive token queries
**File**: `lib/acai/teams/teams.ex:222-249`
**Change**: Single query that returns both active and inactive tokens

**Example implementation**:
```elixir
def list_team_tokens_split(%Team{} = team) do
  now = DateTime.utc_now()
  
  tokens =
    Repo.all(
      from t in AccessToken,
        where: t.team_id == ^team.id,
        order_by: [desc: t.inserted_at],
        preload: [:user]
    )
  
  Enum.split_with(tokens, fn t ->
    is_nil(t.revoked_at) and (is_nil(t.expires_at) or DateTime.compare(t.expires_at, now) == :gt)
  end)
end
```

**Expected impact**: Reduces 2 queries to 1 on initial page load (saves ~10-20ms)

**Verification**: Measure query count before/after using Ecto telemetry or test assertions.
