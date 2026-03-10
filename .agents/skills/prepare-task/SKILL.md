---
name: prepare-task
description: If someone asks you to prepare, plan and assign a task.md file, building a feature.yaml spec
---

We use task `.md` files when assigning chunks of work as part of our spec-driven development workflow.
We are either implementing 1 entire feature spec, or aligning / refactoring / fixing code to meet some acceptance criteria defined in the spec.

Our feature specs are defined in `*.feature.yaml` files

The resulting task files must be comprehensive and complete, the developer who reads it should not need any outside resources, and will not need to read the spec themselves.

**What makes a good task assignment?**
- Comprehensive research and exploration of the current codebase. Points the developer to existing tools and components that may be useful for this task
- Considers dependant and prerequisite work
- Includes clear action items / todo boxes to check
- Always lists every acceptance criteria to be satisfied, with their complete ACIDs e.g. `my-feature.COMPONENT.1-1` and requirement text
- Excludes irrelevant and unrelated details
- Doesn't micromanage: avoid deciding new variable names, new components, new file paths, etc. unless taken from spec. Only demonstrate critical concepts and patterns.
- **Never** edit a `feature.yaml` file unless asked to
- Always stay true to the spec

# Requirements
* [ ] Read relevant feature spec .yaml files.
* [ ] If you determine the feature is still blocked or needs prerequisite work that is out of scope for this task, halt and notify the supervisor.
* [ ] Output 1 or more task files. If the work is complex, break it into phases - 1 phase per task file.
