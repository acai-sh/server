# High Priority
* [ ] Abuse prevention - need to rate limit push api and limit payload as well.
* [ ] Including states is too confusing, need to separate that
* [ ] Fix States-only push (critical bug) - `resolve_existing_implementation:640`
      When pushing states without specs, the code uses Enum.find by name only:
      `case Enum.find(implementations, &(&1.name == target_impl_name)) do`
      If Product A and Product B both have a "production" implementation, and a branch is tracked by both:
      - Enum.find returns the first match (order depends on DB query)
      - No validation exists because there are no specs to validate against
      - States get written to the wrong implementation - silent data corruption
* [ ] Requirement string can be empty/optional (to support deprecated: true standalone)
# Other TODOs

* [ ] acai-ignore line to deal with ACID clashes? Or a configurable prefix to decrease the likelihood?
* [ ] Add max length requirements to core (feature names, impl names, etc)
* [ ] feature.yaml draft mode — if draft: true, safe to renumber ACIDs. Default draft: false. Warn if draft but ACIDs are detected in codebase.
* [ ] Show last_used in Access Tokens view
* [ ] Should add embedded schemas for spec.requirements, feature_impl_state.states, and feature_Branch_ref.refs
* [ ] Explore ways to reduce friction around spec diffing (right now its just gitops)
* [ ] Explore Journeys (gherkin)
* [ ] Future idea - Filter by --product, not needed now because we can filter by feature-name.


## Prune Concepts

- A feature spec that is not tied to an impl, because all the impls were deleted (still appears in nav bar).
- Branch entities that were pushed but aren't tracked (or had their impl deleted). Currently branches can not be deleted / cleared.
- Feature_impl_states that can't be seen because the spec was deleted from the branch (on impl. deletion they are cascade deleted).
- feature_branch_refs that can't be seen because there are no long any impls tracking that branch, or because there are no specs for that feature, or because the specs are stranded.

## API Test

We are performing an experiment where we simulate a CLI interacting with an API. The goal is to battle test a few scenarios to ensure the /push endpoint is working as expected.
The api endpoint is on localhost - `http://localhost:4002/api/v1/push`
I have created a token for you to use in the Authorization header: `Bearer at_R04UL_-oHRq3-fQ2Xh6SUOoY2HeQnJVDK4WwH9AAdPc`

You are expected to do the 'magic' that a cli would normally do for us here, which is:
- Determine the repo_uri
- Determine the branch name
- Determine the commit hash
- Scan the repo for code references to ACIDs (storing the file path + line of code, and recording the is_test: true boolean if that ref was in a test file)
- Parse the feature.yaml to extract requirements, requirement notes, product and feature name, etc.
- Assemble the request body that includes specs, states, refs, and metadata
- Submit an authenticated network `post` to the `/push` endpoint

In addition, for debugging, please put the complete payload of each experiment in `/tmp/api-test/experiment<number>.json` so that I can see what was sent.
Optionally, if you identify is other debug data worth recording, you can put that in a similar `experiment<number>.txt` file.

You can find the complete openapi.json in `/tmp/openapi.json`

If the api is not accepting your data, and you believe the request is properly formatted, please do not proceed.
Once the api accepts your push, do not proceed

# Experiment 1 - Net new content
In this first experiment we simulate pushing 1 brand new spec, for a new product and feature, that has already been completed.
The actual spec is in `features/site/data-model.feature.yaml`
For every ACID in the spec, mark a state `completed` (remaining can have no states).
When you parse refs, filter out any refs that are not related to the data-model feature. e.g. we keep `data-model.TEAMS.1` and omit `nav.PANEL.1`

The imaginary cli call would have looked like this;
```sh
# Pushing the feature spec and all related code refs in this repo, with states completed
# The cli would have scanned the filesystem from repo root to find the feature file, and related refs in code and tests.
acai push data-model --states '{ ...completed_acids }'
```

# Experiment 2 - idempotency test
Repeat the above, identically


# Experiment 3 - just state updates
```sh
# Pushing a key-value map (json format) of ACID keys to state objects
acai push --states '{ ...acids }'
```

# Experiment 4 - branch from parent

## Re-evaluating multi-product repos
In some cases we force the user to namespace their pushes with `--target <product-name>/<implementation-name>`.
This is because it is common for the user to be in a monorepo with many products (api, microservice, mobile-android, mobile-ios, webapp).
If all of those products have a similarly named implementation, e.g. `Production`, we wouldn't know where to apply `states`.

### From a monorepo with many specs for **multiple products**, I can use the CLI to push from...

#### A new branch, (without parent), (without targets)
- JTBD: I want to set up acai for the first time ever. Or I forgot to choose a parent to inherit from. Or this runs on a CI on every new branch push.
- The CLI splits it into individual API calls by `product-name/impl-name` target
- For each, the server creates the new product, the new impl, inserts specs and refs, tracks the branch.
- User can go in later and link it to a parent if they need to.
- Any valid acai ref is included

#### A new branch, with parents, (without targets)
- JTBD: I want to set up `dev` to track `main` for all my products.
- CLI accepts `--parent product-a/parent-name product-b/parent-name` list of product/name keys.
- CLI splits this into single calls. The api only needs `product` from the yaml and falls back to branch name.
- If a spec is pushed and can't be mapped to a parent, it should throw. The user should be invited to include 1 parent arg for each, or use `feature-name` args to narrow it down. Or `--product` filter in the future.
- Any valid acai ref is included

#### A new branch, with parents, with targets
- JTBD: I want apply multiple custom-named implementations to multiple parent implementations, in a single call.
- CLI accepts `--parent product-a/parent-name product-b/parent-name` list of product/parent-name keys.
- CLI accepts `--target product-a/new-impl product-b/new-impl` list of product/new-impl-name keys
- CLI splits this into single calls. The api only needs `product` from the yaml and `target_impl_name`, and can set up new implementations with inheritance.
- Any valid acai ref is included

#### Any of the above, filtered by `feature-name`
- JTBD: I want to push some changes I made, restricted to a feature, to reduce payload size or to omit unfinished work.
- All of the above cases are the same, just a filtered version (fewer specs included)
- Refs are filtered by feature-name (just to reduce payload)

#### From an existing tracked branch, (without parent), (without targets)
- JTBD: I want to tweak a spec or refs and push them, or have my ci auto-push them on merge
- The branch is already tracked, so the API should not create new implementations

#### From an existing tracked branch, with parent
- JTBD: I pushed and established parent, and then reused the same command again
- We should silently ignore the parent arg to support idempotency, proceeding as usual (update case)
- We don't support updating the inheritance tree via the `push` endpoint.
- Optionally, we can detect when the parent does not match any existing implementation, which tell us this is not the idempotency case, and we can error/warn (nice-to-have).

#### From an existing tracked branch, with targets
- JTBD: I pushed and established parent/child relationship for a new impl, and then altered specs/code and reused the same command again
- We don't support creation of new implementations if the branch is already tracked.
- API detects when the current branch is already tracked by an impl other than the given target, and errors
- If the target is already established, proceed as usual (update case)

### And handles the case where...
#### An existing branch is tracked by multiple impls already
- This is the update case - api handles writing refs to feature_branch_refs, and specs with tracked_branch_id
- All branches will receive updates

#### A target product/impl already exists
- Applies updates (idempotent update case), unless the current branch is not tracked by that target impl, in which case it throws.

#### The user already pushed a spec without parent, then runs it again with parent.
- Should probably error and say, this impl already exists. Can delete old and try again or can try with new name.

### And does does NOT handle...
- Renaming an impl if it's already established.
- Updating the inheritance tree via the `push` endpoint.
- Creation of new implementations if the current branch is already tracked by a different impl.

## Decisions:
- `push --all` should push all specs for all products, even though the API only accepts 1 product at a time. Under the hood, the CLI must do this in batches.
- filters (`feature-name`, in the future product-name) should also apply to refs, if only to reduce the payload size, and for predictable behavior. However it should be noted that, work on 1 feature often can lead to regressions of another feature, so push --all is encouraged.
- We do not support creation of an implementation by push from a branch that is already tracked by a different implementation (too complex). The user can accomplish this by editing tracked branches.

## Next steps

- Update states specs and remove them
- Document these journeys in the CLI repo
- Make sure the API handles these journeys appropriately
