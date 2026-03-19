# High Priority
* [ ] Abuse prevention - need a max number of specs, refs, etc.

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

UI actions

JTBD:
"The `fix-map-settings` work has been merged to `dev` so we can delete that implementation"
"Staging has been merged to `main` so we can reset those states and inherit them instead"

Spec alterations; please adjust the specs to add these new requirements. I'm adding 2 new features, which are the 2 settings drawers, and 2 buttons to the feature-impl-view that trigger the drawers.

# feature-settings
Spec outline for the Feature Settings Drawer which for now is only rendered in the feature-impl-view

Clear States:
  - Renders a Clear States button
  - If there are no feature_impl_states for this feature + impl, this button is disabled (including the case where all states are inherited)
  - On click, triggers a confirmation modal
  - On confirm, clears all the states for this feature (feature_impl_states)
  - The UI is updated immediately to reflect either no states, or inherited states (if the feature can inherit states from a parent impl.)

Clear Refs
  - Renders a Clear Code Refs button
  - If there are no feature_branch_refs for any of the tracked branches of this implementation, this button is disabled (including the case where all refs are inherited).
  - On click, triggers a confirmation modal
  - The confirmation renders a branch picker (multi-select) that lists all tracked branches for this implementation.
  - On confirm, clears all the refs for each of the the selected branches for this feature (feature_branch_refs)
  - The UI is updated immediately to reflect either no refs, or inherited refs (if the feature can inherit refs from a parent impl.)

Delete Spec
  - Renders a Delete Spec button
  - If the target spec is inherited from a parent, this button is disabled.
  - On click, triggers a confirmation modal
  - On confirm, deletes the target spec for this tracked branch
  - The UI is updated if a parent spec can be inherited, or redirected to /p/:product_name if a parent spec can not be inherited for this feature.
  - Note: the updated UI shows the parent's requirements, as the previous target_spec's requirements are discarded. The UI should support partial-application of refs and states by ACID (for example, some ACIDs will have been removed, and some will have been restored, and the UI should already be built to gracefully and silently handle this).

# impl-settings
Spec outline for the Implementation Settings drawer which for now is only rendered in the feature-impl-view

Rename Implementation
 - Renders the current implementation name in a text input
 - Renders a save button
 - On click, saves the name
 - Handles error if db rejects it (e.g. product already has implementation with this name)

Untrack a branch
 - Lists all tracked branches and a delete icon button for each
 - The delete icon button is disabled for the branch that contains the target spec for the feature we are currently viewing
    - Note: we assume it is probably not the user's intention to delete the feature they are currently viewing
 - On click, triggers a confirmation modal
 - On delete, the feature-impl-view ui is updated, which can result in some refs disappearing.
 - If the user changes their mind, they can re-track the branch and nothing is destroyed.

Track a branch
 - Shows a dropdown or list that renders all the trackable branches (shows full repo_uri plus branch name)
   - Does not list untrackable repos/branches. A trackable branch is: any branch record for the current team_id, with a repo_uri that is not already tracked by this implementation.
 - Renders a Save and a Cancel button
 - User can select one, and confirm it by clicking save, or clear it by clicking cancel
 - On save, the branch is added to the list of tracked branches, and the ui is updated immediately
 - On cancel, the branch is deselected and nothing else changes.

Delete Implementation
 - Renders a Delete Implementation button
 - On click, opens a confirmation modal
 - Confirmation modal renders the name of the implementation, the product name, and a Delete button, and a Cancel button
 - The confirmation modal explains that this is irreversible. All associated features will have their states and statuses cleared for this implementation. If any children are inheriting from this implementation, they will not be deleted, but they will lose any inherited states or references that came from this implementation.
