TODO:
* [ ] Should I have version fallback to branch-name just to reduce risk of conflict?
* [ ] separate tracked_branches and branches tables
* [ ] swap branch_name for branch_id
* [ ] Document the inheritence / push patterns - when do we push new spec versions, how do we avoid having to push 100s of specs every time we sync a new working branch / implementation? One benefit of keeping explicit versioning is that is an easy way to detect intent; we could just try to update / insert all specs and silently fail on conflicts.



## Spec pushes are rejected when:

**This feature + version is already taken.**
  -> The system tried to insert a new spec version, but failed because this feature + version exists already. You can simply change the feature.version, the feature.product, or the feature.name and try again. Most likely, you encountered this while pushing a spec from a new branch.
**This implementation name is already taken**
  -> The system tried to create a new Implementation of a product, but failed because the implementation name must be unique. If you do not include an implementation name in the params, the branch name is taken as a fallback.
**The target implementation does not track the source branch**
  -> The push included a target implementation (name or id) which is already tracking a different branch in this repo. You must choose a new implementation name, or omit the implemtnation name, or update the tracked branches for that implementation and try again. Target implementation was: <name, id>, source branch was: <source_branch_name>
  


## Push journeys / paths to push outcomes

---

# Brainstorm
Inheritence, spec tracking and push-all vs push-one.
Imagine I have 5000 features in a large monorepo with many requirements in each. To "snapshot inherit" I would write all statuses and refs to 5000 new rows. I could leave the specs where they are, but it's still a heavy operation.

A less write-heavy solution would be an opt-in-per-feature model. In this model, I would specify which specs to push. Already, each spec version is associated to one or more impls. via spec.branch_id -> tracked_branches -> impl. So if I am creating a new implementation, for a new branch, i may only run `push` for 1 feature, and so that spec, and only its refs get pushed?

But it's a MUST HAVE FEATURE that when I change any refs for any feature on a tracked branch, I want to see those changes reflected in my dashboard on push. For example, if I am working on feature-b, but i accidentally remove a test related to feature-a, I want to open my dashboard and see that we are now missing test coverage for feature-a.

So if this is a must have, we end up in a situation where we need may be pushing thousands of refs and filepaths every time we sync our work, or commit, or merge. The optimization here is, for downstream branches, to use git diff and only grep changed files.

Ideally we could know which refs we care about, to reduce our search space. We could imagine a handshake where we first ask, which implementations are tracking this branch, and which specs? and traverse inheritance chain as well. The api responds with a list of feature-names which we use to shrink the dictionary. I'm not sure that really solves problems, most likely we are better off just grepping the whole repo-- plus that helps us spot dangling refs. Whats the downside? We push refs that are far away in our monorepo from the space that we were working in. Maybe a better solution is to trust inheritance, and only grep on changed files.

---
Conclusion: Inheritance, snapshot and ref optimization.

Every implementation should choose a `parent`.

---

How do we apply states to a downstream implementation, without a downstream spec?
Let's say I create a new implementation called `backend/experiment` from parent `Staging` impl. And then on that working branch, I introduce a regression, and eliminated some code refs. When I push, my git diff will surface the refs that change, and so we push a partial map of refs, and maybe some states as well. For both buckets the parent bucket and snapshot is written to a new spec_impl_refs.
But the challenge is, what spec am I referencing? If I did not alter nor push the same spec on my experiment branch, then I would naturaly be referencing the spec version that was pushed from staging.
One option would be to always push the specs for any refs or states that get changed locally? But that wouldn't work if the specs are on the `frontend` repo and im making changes on the backend repo.
And so another option would be to change the spec_impl_refs table and have it be `feature_imlp_refs` which is not strictly tied to a spec version, but instead is conceptually associated with the "nearest spec version". So instead of `spec_id` it defines `feature_name` which is always just the prefix of all the ACIDs contained in it. How would that impact queries?
