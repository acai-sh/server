---
name: prepare-task
description: Use when asked to plan and prepare a task towards implementation of a feature.yaml spec
---

If asked to plan and prepare a task, your job is to study the codebase to write an informed plan of attack for building the assigned feature.

The task will include everything needed to implement 1 feature as specified in a `feature.yaml` spec.

**What makes a good task assignment?**
- Comprehensive research and exploration of the current codebase. Points the developer to existing tools and components that may be useful for this task.
- Includes clear action items / todo boxes to check
- Lists all acceptance criteria to be satisfied, with their complete ACIDs e.g. `my-feature.COMPONENT.1-1` and requirement text
- Excludes irrelevant and unrelated details.
- **Only uses code snippets sparingly to demonstrate critical concepts and patterns. Let your devs do the coding**.
- Doesn't micromanage: avoid deciding new variable names, new components, new file paths, etc. unless taken from spec.
- Does not add new acceptance criteria that weren't already defined, never alter the spec

# Requirements
* [ ] Read the feature spec file in `/features/{feature_name}/feature.yaml`
* [ ] If you determine the feature is still blocked (see prerequisites field in feature.yaml), halt and notify the supervisor.
