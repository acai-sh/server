# high prio
* [ ] Make implementation names globally unique in the team, which simplifies a lot of edge cases like linking and state push, but as a tradeoff it prevents initializing multi-product push
* [ ] refactor this data model spec and our system-design.md doc so that instead of feature_impl_refs, we track `feature_branch_refs` which belong to a branch_id.

# other
* [ ] acai-ignore line to deal with clashes? or a configurable prefix to decrease the likelyhood?
* [ ] Add max length requirements to core
* [ ] I have concerns about inheritance queries so need to review those
max payload size for push?

When we pass a ref for auth.LOGIN.1 it is possible that:
- 2 products in the team have a feature called auth
- both of those products have an impl that is tracking this branch (e.g. auth-microservice/main)
-> acai is fine with this. When we push refs, we key them on feature+repo+branch
-> when we query for a given acid or feature, we must always identify the implementation. 

The query is "for every tracked branch, grab the refs for this feature" and respect inheritance.
  Start with known impl id and feature name
  -> find tracked branch ids
  -> for `feature_branch_refs` find rows where branch_id matches and feature_name matches
  -> if none found repeat for impl.parent_implementation_id

What if I want to clear my applied states and revert back to inheritance?

tidy spec - say 'user' vs first person?

need a way to manage branch linking in the ui

feature.yaml - if it's a draft, it's safe to renumber and reorder ACIDs. default is draft: false. Warn if draft is true but ACIDs are detected.
