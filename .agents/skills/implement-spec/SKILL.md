---
name: implement-spec
description: Learn how to write code that satisfies requirements defined in feature.yaml specs
---

We write high quality specs before assigning them for implementation. Specs are in `/features/**/*` in `feature.yaml` files

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

Specs are simple, behavior focused, and user oriented. Use your best judgement to fill in gaps in the spec as you are an expert engineer.

When you resolve a requirement, you MUST leave code comments with the ACID (just the id! not the text!). These comments help us understand "why" that code was written, and are used to generate a reference graph.
Never do partial ACIDs, they are too difficult to search for. Full id only.
**Never** duplicate spec requirement text in comments. You must only write the ACID on it's own. If you ignore this requirement, you will ruin our codebase.
You must write at least one unit test for every ACID, or a dummy test if not testable.
**Never change the spec** unless explicitly asked to change it.
