# High Priority
* [ ] Abuse prevention - need to rate limit push api and limit payload as well.

# Open questions

* [ ] acai-ignore line to deal with ACID clashes? Or a configurable prefix to decrease the likelihood?
* [ ] Add max length requirements to core (feature names, impl names, etc)
* [ ] feature.yaml draft mode — if draft: true, safe to renumber ACIDs. Default draft: false. Warn if draft but ACIDs are detected in codebase.
Think of a concept for backtracking or handling dead links when an implementation / feature is removed?

UI actions

JTBD:
"The `fix-map-settings` work has been merged to `dev` so we can delete that implementation"
"Staging has been merged to `main` so we can reset those states and inherit them instead"

Spec alterations; please adjust the specs to add these new requirements. I'm adding 2 new features, which are the 2 settings drawers, and 2 buttons to the feature-impl-view that trigger the drawers.

## Prune Concepts

- A feature spec that is not tied to an impl, because all the impls were deleted (still appears in nav bar).
- Branch entities that were pushed but aren't tracked (or had their impl deleted). Currently branches can not be deleted / cleared.
- Feature_impl_states that can't be seen because the spec was deleted from the branch (on impl. deletion they are cascade deleted).
- feature_branch_refs that can't be seen because there are no long any impls tracking that branch, or because there are no specs for that feature, or because the specs are stranded.
