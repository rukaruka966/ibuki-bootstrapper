name: Feature request
description: Describe an outcome that the project should make possible.
body:
  - type: markdown
    attributes:
      value: |
        Describe the problem and the result that would satisfy the request. An AI
        agent will derive implementation details, tests, and completion criteria.

  - type: input
    id: component
    attributes:
      label: Component
      description: Name the application, system, module, or workflow involved, when known.

  - type: textarea
    id: problem
    attributes:
      label: Problem
      description: Describe the limitation, friction, or unmet need to solve.
      placeholder: What is difficult or impossible today?
    validations:
      required: true

  - type: textarea
    id: desired-outcome
    attributes:
      label: Desired outcome and human acceptance
      description: Describe the observable result that would make the request complete.
      placeholder: What should a person be able to do or observe?
    validations:
      required: true

  - type: textarea
    id: scope
    attributes:
      label: In scope
      description: List behavior or artifacts that should be included, when already known.

  - type: textarea
    id: out-of-scope
    attributes:
      label: Out of scope
      description: List behavior or artifacts that should not be changed, when already known.

  - type: textarea
    id: constraints
    attributes:
      label: Constraints and stop conditions
      description: Note request-specific compatibility, safety, or decisions that require human confirmation.

  - type: textarea
    id: context
    attributes:
      label: Additional context
      description: Add sanitized alternatives, related issues, examples, or reference material.

  - type: checkboxes
    id: public-report-safety
    attributes:
      label: Public report safety
      description: Confirm that this issue is safe to publish if the repository is public.
      options:
        - label: This issue contains no secrets, tokens, personal information, private URLs, or local private paths.
          required: true
        - label: This issue contains no undisclosed security vulnerability details.
          required: true
