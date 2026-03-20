# High Priority
* [ ] Abuse prevention - need to rate limit push api and limit payload as well.

# Other TODOs

* [ ] acai-ignore line to deal with ACID clashes? Or a configurable prefix to decrease the likelihood?
* [ ] Add max length requirements to core (feature names, impl names, etc)
* [ ] feature.yaml draft mode — if draft: true, safe to renumber ACIDs. Default draft: false. Warn if draft but ACIDs are detected in codebase.
* [ ] Show last_used in Access Tokens view
* [ ] Should add embedded schemas for spec.requirements, feature_impl_state.states, and feature_Branch_ref.refs

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
