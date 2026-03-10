# Task: Add silent option to Acai.Seeds.run()

## Background
When running tests, the `Acai.Seeds.run()` function outputs many `IO.puts` messages to the console because the seeds_test.exs file calls this function. This creates noise in the test output.

## Goal
Add a `silent: true` option to `Acai.Seeds.run/1` that suppresses all console output when enabled.

## Implementation Plan

### 1. Modify `lib/acai/seeds.ex`

Change the `run/0` function to `run/1` accepting options:
- Add `opts \\ []` parameter
- Extract `silent = Keyword.get(opts, :silent, false)`
- Pass `silent` parameter to all private seed functions:
  - `seed_users(silent)`
  - `seed_team(name, silent)`
  - `seed_roles(team, users, silent)`
  - `seed_products(team, silent)`
  - `seed_specs(team, products, silent)`
  - `seed_implementations(team, products, silent)`
  - `seed_tracked_branches(impls, silent)`
  - `seed_spec_impl_states(specs, impls, silent)`
  - `seed_spec_impl_refs(specs, impls, silent)`

Update all private functions to accept and use the `silent` parameter:
- Wrap all `IO.puts` calls in `unless silent do ... end`

### 2. Modify `test/acai/seeds_test.exs`

Update all calls to `Acai.Seeds.run()` to `Acai.Seeds.run(silent: true)`:
- Line 28 in setup block
- Line 51 in idempotent users test
- Line 83 in idempotent teams test
- Line 109 in idempotent products test
- Line 208 in idempotent specs test
- Line 251 in idempotent implementations test
- Line 285 in idempotent tracked branches test
- Line 340 in idempotent spec_impl_states test
- Line 405 in idempotent spec_impl_refs test

## Acceptance Criteria
- [ ] `Acai.Seeds.run(silent: true)` produces no console output
- [ ] `Acai.Seeds.run()` (default) still produces normal output
- [ ] All existing tests pass
- [ ] Changes committed to feat/product-feature-views branch
