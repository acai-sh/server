# Open questions

* [ ] acai-ignore line to deal with ACID clashes? Or a configurable prefix to decrease the likelihood?
* [ ] Add max length requirements to core (feature names, impl names, etc)
* [ ] Max payload size for push endpoint?
* [ ] Review inheritance queries for performance — worst case depth is 3-4 levels
* [ ] What if I want to clear my applied states and revert back to inheritance?
* [ ] Need a way to manage branch linking in the UI
* [ ] Tidy spec voice — use "user" vs first person consistently?
* [ ] feature.yaml draft mode — if draft: true, safe to renumber ACIDs. Default draft: false. Warn if draft but ACIDs are detected in codebase.
Think of a concept for backtracking or handling dead links when an implementation / feature is removed?
* [ ] Is it enough to grab from git origin? What happens if there is no repo_uri? Allow user to provide anything?

---

plan of attack
- QA verification of seed data
- Review core views to ensure performance
- API simulation of `push` and light review of the push api code
- clean up reference concepts in UI

--
feat/feature-impl-view-revision QA feedback

Please take these notes, compare them to the spec. If they differ radically from the spec requirements, or are key behaviors that are missing from the spec, please let me know. Otherwise, fix the issues.

items with [design] tag are never in specs, just fix these outright.

[product-view][design] product overview matrix, let's put the cube icon next to each feature title (row header)

[feature-impl-view][spec] Should render feature description from the target spec
[feature-impl-view][bug] the requirement details for requirements in the `feat/ai-chat` implementation of inherited features, say `status: (accepted) (feat/ai-chat)` which is misleading, the status was not accepted on the feat/ai-chat implementation. As indicated by the `Inherited` badge in the Requirements Coverage card, these states were all inherited from an ancestor implementation. We should update this to show the same Inherited badge with the same popper and tooltip as we have on the requirements coverage card.
