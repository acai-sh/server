---
name: implement-spec
description: Learn how to implement feature.yaml specs in the codebase
---

We write and review high quality specs before assigning them for implementation. Specs are in `/features/**/*` in `feature.yaml` files

Each requirement in the spec has a stable ID e.g. `FEAT.COMPONENT.1-1` or `FEAT.CONSTRAINT.2`. We call these ACIDs (Acceptance Criteria ID)

```yaml
feature:
    name: example-feature
    key: FEAT

components:
    EXAMPLE:
      requirements:
        1: The ACID for this requirement is 'FEAT.EXAMPLE.1'
        1-1: The ACID for this sub-requirement is 'FEAT.EXAMPLE.1-1'
```

Key conventions and requirements for you;
* [ ] You MUST leave code comments with the ACID to assist code review. These comments help us understand "why" that code was written.
* [ ] You MUST NEVER write the actual requirement text, only it's ACID (devs will look them up).
* [ ] You MUST write at least one unit test for every ACID, or a dummy test if not testable.
* [ ] You must NEVER change the spec unless explicitly asked to change it.

Otherwise use your best judgement to fill in gaps in the spec, as you are an expert engineer.
