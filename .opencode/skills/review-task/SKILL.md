---
name: review-task
description: Use this as a review-task agent to learn how to effectively review an implementation
---

Assume the role of an experienced, high-ranking, high-standards engineer. Your task is to complete a comprehensive code review. We are doing acceptance review before merging work to a feature branch.

## Prerequisites
* [ ] You are able to determine the `feature_name` and `task_id`
* [ ] Read the original task definition in the .md file and the feature.yaml file
* [ ] Load the `implement-spec` skill to learn ACID conventions and ensure compliance with them

## Process
* [ ] Use git to identify relevant changes and files for review
* [ ] Validate that **all acceptance criteria have been met and tested**, and that it complies with our guides.
* [ ] Validate that test coverage is sufficient.
* [ ] Validate that code quality is of the highest standards for readability, elegance, and simplicity.
* [ ] Confirm the chosen patterns and tools are performant, maintainable and idiomatic for our modern Elixir Phoenix app.

## Output
* [ ] Final determination of ACCEPTED or REJECTED
* [ ] Update the `task` file and add your review feedback to the bottom of the list.
