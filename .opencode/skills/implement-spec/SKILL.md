---
name: implement-spec
description: Learn how to implement feature.yaml specs in the codebase
---

We write and review high quality specs before assigning them for implementation. Specs are in `/features/**/*` in `feature.yaml` files

Each requirement in the spec has a stable ID e.g. `my-feature.COMPONENT.1-1` or `my-feature.CONSTRAINT.2`. We call these ACIDs (Acceptance Criteria ID)

```yaml
feature:
    name: my-feature

components:
    EXAMPLE:
      requirements:
        1: The ACID for this requirement is 'my-feature.EXAMPLE.1'
        1-1: The ACID for this sub-requirement is 'my-feature.EXAMPLE.1-1'
```

Specs are simple, focused on functionality only, and already approved. Use your best judgement to fill in gaps in the spec as you are an expert engineer.

* [ ] You MUST leave code comments with the ACID to assist code review. These comments help us understand "why" that code was written.
* [ ] NEVER duplicate spec requirement text in comments. You must only write the ACID on it's own. If you ignore this requirement, you will ruin our codebase by creating spam and tight coupling between spec and code.
* [ ] You MUST write at least one unit test for every ACID, or a dummy test if not testable.
* [ ] You must NEVER change the spec unless explicitly asked to change it.
