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
[product-view][spec] We should sort by inheritance, from start (left) to end (right) (respecting language LTR / RTL of course), with parentless implementations first, and related children after it.
For example if we had `Prod` and `Staging` and `Feature` as ancestors, but we had a second impl with no parent called `POC1` with a child `POC1.1`, the UI order could be; Prod, Staging, Feature, POC1, POC1.1, or it could be POC1, POC1.1, Prod, Staging, Feature. Because POC1 and Prod are both parentless, followed by their children.
[product-view][spec] we should disable the cell link and indicate when an implementation does not have a feature. Specifically, this is the case when a spec was introduced on a child implementation, and so that spec has not yet been merged to the parent that I am trying to click, if unhandled this leads to an error (in current code).

[feature-impl-view][spec] Should render feature description from the target spec
[feature-impl-view][bug] the requirement details for requirements in the `feat/ai-chat` implementation of inherited features, say `status: (accepted) (feat/ai-chat)` which is misleading, the status was not accepted on the feat/ai-chat implementation. As indicated by the `Inherited` badge, these states were all inherited from an ancestor implementation. We should update this to show the same Inherited badge with the same popper and tooltip as we have on the requirements coverage card.

[feature-view][spec] In the feature overview, we should simply not render implementation cards if those implementations don't have or inherit a spec for that feature.

[feature-view][bug] In the feature overview for some features, like `api / core`  I can't click Production card to go to `http://localhost:4000/t/mapperoni/i/production-019cf4d025b87e7f8de49371993e01be/f/core`. It renders a flash saying Feature not found for this implementation. It's clear to me that this is a test gap - tests should not be passing if this bug exists. I doubt that it is a seed data issue, because I had specified that we want `main` to have specs. For `site`, this is similar except it is only the implementations with 0% progress

# In progress
[product-view][bug] I am not able to navigate from the product overview or the feature overview to any of the api implementations - neither core nore mcp features, nor production or staging implementations.
