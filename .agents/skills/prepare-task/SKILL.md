---
name: prepare-task
description: Use when asked to prepare a task.md for part or all of a feature.yaml
---

If asked to plan and prepare a task, your job is to study the codebase to write an informed plan of attack for building the assigned feature.

The task will include everything needed to implement 1 feature as specified in a `feature.yaml` spec.

**What makes a good task assignment?**
- Comprehensive research and exploration of the current codebase. Points the developer to existing tools and components that may be useful for this task
- Consider dependant and prerequisite work
- Includes clear action items / todo boxes to check
- Always lists every acceptance criteria to be satisfied, with their complete ACIDs e.g. `my-feature.COMPONENT.1-1` and requirement text
- Excludes irrelevant and unrelated details
- Doesn't micromanage: avoid deciding new variable names, new components, new file paths, etc. unless taken from spec. Only demonstrate critical concepts and patterns. Let your devs do the coding!
- **Never** alter the spec unless asked to

# Requirements
* [ ] Read the feature spec file in `/features/{feature_name}/feature.yaml`
* [ ] If you determine the feature is still blocked (see prerequisites field in feature.yaml), halt and notify the supervisor.
