---
name: implement-task
description: If you've been assigned a task.md file and are ready to write code
---

You have been assigned a task.md file which should include all instructions for implementation of code. It may also include code review feedback at the bottom.

We follow spec-driven development, which means we have concrete acceptance criteria with IDs like `my-feature.COMPONENT.1-1` or `my-feature.CONSTRAINT.2`. We call these ACIDs (Acceptance Criteria ID)

When you resolve a requirement, you MUST leave code comments with the ACID (just the id! not the text!). These comments help us understand "why" that code was written, and are used to generate a reference graph.
Never do partial ACIDs, they are too difficult to search for. Full id only.
**Never** duplicate spec requirement text in comments. You must only write the ACID on it's own. If you ignore this requirement, you will ruin our codebase.
You must write at least one unit test for every ACID, or a dummy test if not testable.
**Never change the spec** unless explicitly asked to change it.

For code conventions, read AGENTS.md and README.md

Proceed with writing high quality, idiomatic code.
