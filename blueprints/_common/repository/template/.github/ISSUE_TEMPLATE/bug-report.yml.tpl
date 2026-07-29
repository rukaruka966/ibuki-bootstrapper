name: Bug report
description: Report behavior that differs from the expected project outcome.
body:
  - type: markdown
    attributes:
      value: |
        Describe what you observed and what result you expected. An AI agent will
        structure implementation details and verification criteria during triage.

  - type: input
    id: component
    attributes:
      label: Component
      description: Name the application, system, module, or workflow involved, when known.

  - type: textarea
    id: observed-behavior
    attributes:
      label: Observed behavior
      description: Describe what happened, including any partial output or side effects.
      placeholder: What did you see?
    validations:
      required: true

  - type: textarea
    id: expected-behavior
    attributes:
      label: Expected behavior
      description: Describe the result you expected from the same operation.
      placeholder: What should have happened?
    validations:
      required: true

  - type: textarea
    id: reproduction
    attributes:
      label: Reproduction
      description: |
        List the smallest known sequence that triggers the behavior. If it is not
        reproducible yet, write "Not yet reproducible" and describe when it occurred.
      placeholder: |
        1. Run ...
        2. Perform ...
        3. Observe ...
    validations:
      required: true

  - type: textarea
    id: environment
    attributes:
      label: Environment
      description: Include only versions and configuration relevant to reproducing the behavior.

  - type: textarea
    id: impact
    attributes:
      label: Impact
      description: Describe what work is blocked or what incorrect result remains.

  - type: textarea
    id: evidence
    attributes:
      label: Evidence
      description: Add sanitized logs, screenshots, or links that help reproduce or diagnose the behavior.

  - type: textarea
    id: constraints
    attributes:
      label: Constraints
      description: Note request-specific compatibility, safety, or change boundaries. Leave empty when none are known.

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
