# System Design & ADR

This document provides an overview of key system design decisions for acai.sh, which is a tool for spec-driven development.

Acai.sh is a cli and api to support a spec-driven development workflow.
- Write requirements and acceptance criteria in `feature.yaml` spec files.
- Run a cli command to extract Acceptance Criteria and their IDs (ACIDs), and push them to a server.
- Use the dashboard, CLI, and API to track implementation progress and to do structured QA and acceptance review.

The result is that AI agents are empowered, by being able to more easily query and search requirements, specs, states, and code refs, even across repos and implementations, which helps them self-assign work and stay on-track when making changes. Humans are also empowered, by having a new cross-sectional view of their products, their feature specs, and the changes that their AI agents are making.

## Mental Model

### What is a Spec?

It is a file like `my-feature.feature.yaml`.
It defines `feature.name` and `feature.product` and a list of requirements.

```yaml
feature:
    name: my-feature
    product: my-website

components:
    EXAMPLE:
      requirements:
        1: The ACID for this requirement is 'my-feature.EXAMPLE.1'
        1-1: The ACID for this sub-requirement is 'my-feature.EXAMPLE.1-1'
```

A spec can have multiple versions, as long as each version lives on a different git branch, and the `feature.version` numbers are different.

The `specs` table maintains 1 row *per spec version*. In other words, insert new specs to the specs table only when:
  -> feature.product + feature.name combo is new (its a brand new feature)
  -> branch + version combo is new (its an iteration of an existing feature)

```elixir
# to prevent user from duplicating a featre on the same branch
create unique_index(:specs, [:product_id, :repo_uri, :branch_name, :feature_name])
# to prevent a user from iterating on specs across branches without changing the version
create unique_index(:specs, [:product_id, :feature_name, :feature_version])
```

Otherwise, we can update existing specs. The following data is mutable in a spec:
  - the `path` (if the feature.yaml file is relocated)
  - timestamps and metadata (last_seen_commit, parsed_at, feature_description, etc)
  - The `version` can be changed
  - `raw_content` and the `requirements` map

# What is an Implementation?

1 product can have many Implementations. An Implementation is a group of related branches, and an optional parent Implementation from which it should inherit state.

For example:
`Production` can track `frontend/main` and `backend/main`, and have no parent
`Staging` can track `frontend/dev` and `backend/dev`, and have `Production` as parent
`experiment-1` can track `frontend/experiment` and `backend/dev`, and have `Staging` as parent

Constraints:
- The implementation name must be unique.
- feature.yaml files must be pushed from one of the tracked branches, or parent implementation's tracked branches, otherwise that feature is 'invisible' to the implementation.
- An implementation may not track two branches in the same repo
```ex
create unique_index(:tracked_branches, [:implementation_id, :repo_uri])
```

Imlement

### Implementation Inheritance

Supported via optional `parent_implementation_id`.

Inheritance makes it possible to quickly spin up a new branch and a new implementation without losing all the refs, status updates, and specs that were pushed to the parent.

It does not copy or snapshot state-- we considered this, but decided it could create too much write overhead in very large repos with hundreds of specs, thousands of reqs and refs.

Instead, we embrace inheritance and traverse the parent graph to resolve states, specs and refs. If a parent drifts far from a child, for example if the child impl. branches are not kept up to date with the parent impl's branches, we accept that the UI and API may return stale data as a known tradeoff. In this situation, the developer always has the option to simply do a 'full push' from the child branch (or, pull upstream git changes down!)

New implementations are created automatically when `push`ing from an untracked branch.

## Data Model
See `setup_database.exs` for complete data model

### Key Tables

`specs` has a row for each 'spec version', and has a `requirements` column which is a map of ACIDs to requirement definitions, notes and flags.

`feature_impl_states` has a `states` column, which is a JSONB bucket for a map of ACIDs to states.
The states we support are `null` or `"assigned|blocked|completed|rejected|accepted"` where null is reflected in the UI and api as "no status"

`feature_impl_refs` has a `refs` column, which is a JSONB bucket for a map of ACIDs to file paths (refs). Ref states have an `is_test` property which allows us to track "requirement test coverage" loosely.

The `feature_impl_states` and `feature_impl_refs` tables are keyed by `(implementation_id, feature_name)` rather than `(implementation_id, spec_id)`. This is intentional, to allow pushing refs without requiring a local spec file. Refs and states are observations about *current code state*, not historical artifacts tied to a specific spec version. The `feature_name` (ACID prefix) is stable across versions.


## CLI (MVP)
<!-- CLI is a work in progress, this may need updating soon -->
Our goal is to have most use-cases covered by a single `acai push` command. This command can be ran locally while developing, or it can be ran on ci / github actions on commits or merges.

The CLI avoids doing a full push of all specs and all refs in your repo, unless you command it to.

`acai push` will try to do a git-aware push by looking at your current implementation branch, comparing it to a parent implementation branch, and pushing only the specs & code refs that have changed.
`acai push --all` will do a full repo scan and push any ref or spec that it finds, regardless of the git state. This is useful for setting up new repositories or for dealing with major drift between parent and child.

## API (MVP)

It's designed to serve the CLI, with some key read endpoints as well.

### `/push`
Push lists of specs, lists of ref maps, and lists of state maps. All lists are optional.
Push actions are idempotent.
When a partial map is pushed, we perform a union of whatever the parent held plus whatever was pushed. For example, if I change a file and add 1 new ref, that gets unioned with all the `feature_impl_refs` in the parent's bucket. Same for states, if I update 1 state downstream.

Refs and states are keyed by `feature_name` (the ACID prefix), not `spec_id`. This allows pushing refs/states from any repo in a monorepo, regardless of where the spec file lives.

Spec pushes are rejected when:
**This feature + version is already taken.**
  -> The system tried to insert a new spec version, but failed because this feature + version exists already. You can simply change the feature.version, the feature.product, or the feature.name and try again. Most likely, you encountered this while pushing a spec from a new branch.
**This implementation name is already taken**
  -> The system tried to create a new Implementation of a product, but failed because the implementation name must be unique. If you do not include an implementation name in the params, the branch name is taken as a fallback.
**The target implementation does not track the source branch**
  -> The push included a target implementation (name or id) which is already tracking a different branch in this repo. You must choose a new implementation name, or omit the implemtnation name, or update the tracked branches for that implementation and try again. Target implementation was: <name, id>, source branch was: <source_branch_name>

## Key User Journeys
There are many ways to edit, branch and iterate on specs and on the code that implements the specs. This covers the key journeys we have considered.
All of these journeys must be supported both locally (after changes are made), as well as on commit & push (via github action), or on merge via ci/cd tooling. They can happen on existing branches (updating existing implementations and specs), or on new branches (to create new implementations).
- Updating an existing spec. For example, tweaking requirements, or relocating the feature.yaml file to a new directory.
- Adding a new spec. For example, specifying a brand new feature.
- Deleting a spec or renaming a feature or product.
- Editing code and tests, leading to new code ref comments.
- Making progress or regressing on an implementation, leading to new states.
- Adding a spec, editing a spec, changing many code refs, and changing many implementation states, all in a single commit.

## Edge Cases

- **Orphaned states:** ACID removed from spec → states/refs retained for reinstatement
- **Branch collisions:** `frontend/main` ≠ `backend/main` (scoped to `repo_uri`)
- **Spec renames:** New `feature_name` = new spec; old spec + states preserved
- **Parent deletion:** `parent_implementation_id` SET NULL, child survives
- **Lazy inheritance:** States/refs are resolved by walking the parent chain on each query, not snapshotted at creation time
- **Cross-repo features:** Refs/states can exist for a feature whose spec lives in a different repo (keyed by feature_name)
