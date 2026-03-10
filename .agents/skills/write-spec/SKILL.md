---
name: write-spec
description: Learn how to write compliant feature.yaml specs
---

Every feature has a spec file called `feature.yaml`
Each requirement in the spec has a stable ID e.g. `my-feature.COMPONENT.1-1` or `my-feature.CONSTRAINT.2`. We call these ACIDs.

Here are tips for writing a good spec;
- Only functionality, never design and style
- Intended behavior, never reflect the current state or status
- Requirements are grouped into obvious components
- Not overly prescriptive, focused only on key behaviors and acceptance criteria
- Always better to under-specify than over-specify

For important cross-cutting criteria that don't relate to a single component, e.g. under-the-hood engineering concerns, use the `constraints` key.

**Less is more. The best spec is a small and concise one.**

`feature.yaml` must be written in a compliant way. Here is the meta-spec that uses a compliant feature.yaml to specify how a feature.yaml should be written.
```
feature:
    name: feature-yaml
    description: A formal specification for compliant feature.yaml files. A self-referential spec-for-the-spec.
    key: FEATURE_YAML
    product: my-product.example.com

components:
    FILE:
      name: Top level file format
      requirements:
        1: The file must be called `feature.yaml`
        2: The file should be located in a file that matches the feature name e.g. `features/my-feature-name.feature.yaml`
        3: The file must begin with the `feature` top-level property, containing feature metadata
        4: The file may contain a `components` top-level property, with unique component keys
        5: The file may contain a `constraints` top-level property, with unique constraint keys

    FEATURE:
        name: Feature metadata
        description: Feature metadata is defined under the top-level `feature` key
        requirements:
            1: Feature metadata must have a `name` field
            1-1: The `name` must be unique within the product
            1-2: The `name` must only contain lower-case chars, numbers, and dashes e.g. `my-feature-name`
            2: Feature metadata must have a `key` field
            2-1: The `key` must be unique within the product
            2-2: The `key` must only contain UPPERCASE chars, numbers, or underscores e.g. `MY_KEY`
            3: Feature metadata may have an optional `description` string
            4: Feature metadata may have an optional `version` string
            4-1: If present, version must follow SemVer
            5: Feature metadata may have an optional `product` string
            6-1: The `product` must only contain upper- and lower-case chars, numbers, underscores, dashes, and periods e.g. `my-product.example.com`
            7: Feature metadata may have an optional `prerequisites` list of strings, which help identify external dependencies that live outside the scope of the spec.

    COMPONENT:
        name: Component groupings, defined under the top level `components` property as unique keys.
        requirements:
            1: The `components` object contains only unique component keys, which are groupings of component requirements (like this one).
            2-1: Component key must only contain upper-case chars, numbers, or underscores e.g. `MY_COMPONENT1`
            2-2: Must be unique within the feature; may not clash with any other group key, neither `component` nor `constraint` key.
            3: Each component group must have a `requirements` field, containing a list of requirements (defined below).
            4: Each component group can have an optional `name` string
            5: Each component group can have an optional `description` string

    CONSTRAINT:
        name: Constraint groupings, defined under the top level `constraints` property as unique keys.
        description: The goal of the `constraints` property is to organize cross-cutting requirements, or criteria that don't fit within a single component.
        requirements:
            1: The `constraints` object contains only unique constraint keys, which are groupings of constraint requirements.
            2-1: Constraint group key must only contain upper-case chars, numbers, or underscores e.g. `MY_CONSTRAINT2`
            2-2: Constraint group key must be unique within the feature; must not clash with any other `component` nor `constraint` key.
            3: Each constraint group must have a `requirements` field, containing a list of requirements (defined below).
            4: Each constraint group can have an optional `name` string
            5: Each constraint group can have an optional `description` string

    REQUIREMENT:
        name: Requirement definitions, defined under the constraint.requirements or component.requirements property.
        description: |
            Requirements are numbered acceptance criteria that live under a component group key or a constraint group key.
            The goal of a requirement is to define a behavior or functionality.
        requirements:
            1: Requirement keys must be integer keys (e.g. `1:`, `2:`, `3:`)
            2: Sub-requirement must associate to a parent requirement's number, using integer-dash keys (e.g., `1-1`, `1-2`)
            3: Sub-requirement keys must never include `-0` as the parent requirement is implicitly the 0th item.
            4: Requirements may be written as any yaml compatible string, including multi-line blocks with markdown, gherkin, etc.
            5: Requirement definitions must describe functional and objective criteria that can be verified as acceptable or not.
            6: Requirements and sub-requirements can be defined as either key-string pairs or key-object pairs
            7: When defined as an object, the object must contain a `requirement` property with the requirement definition string
            7-1: The object may contain a `note` property with a string value
            7-2: The object may contain a `deprecated` property with a boolean value
            7-3: The object may contain a `replaced-by` property with a list of ACID strings
            8: Requirement notes may alternatively be defined in-line and attached to a parent requirement or subrequirement the -note suffix, (e.g. `1-note`, `2-1-note`)

    ACID:
        name: Requirement ID references / Acceptance Criteria IDs (ACIDs)
        requirements:
            1: A requirement can be referenced anywhere in the product via its unique ACID
            2: ACIDs follow the format `<feature-name>.<GROUP_KEY>.<ID>` for example `my-feature.MY_COMPONENT.1-1` or `my-feature.MY_CONSTRAINT.2`
            2-1: feature-name and GROUP_KEY must be uppercase alphanumeric and underscores, to match their definition in the feature.yaml file.
            
constraints:
    EXAMPL:
        name: An example constraint group
        requirements:
            1: This is not a real constraint, just an example of where we define cross-cutting concerns (engineering, security, etc.)
            1-note: This is an example of a comment attached to 'FEATURE_YAML.EXAMPL.1'
```
