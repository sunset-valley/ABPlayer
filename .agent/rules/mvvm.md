---
trigger: mvvm_decision
description: MVVM architecture responsibilities and boundaries
---

# MVVM

- `Model`: owns domain data and pure data transformations.
- `View`: owns UI rendering and user interaction bindings only.
- `ViewModel`: owns presentation/business logic and state orchestration.

# ViewModel Contract

- Define `Input` and `Output` types inside each ViewModel.
- Expose `transform(input:) -> Output` as the primary API.
- Keep side effects and decision logic in the ViewModel, not in the View.

# Boundaries

- Do not place business logic in `View`.
- Do not place UI-specific rendering logic in `Model`.
- Keep responsibilities explicit and one-directional: View -> ViewModel -> Model.

# Testing

- `ViewModel`: unit-test `transform(input:)` behavior with deterministic inputs/outputs.
- `Model`: unit-test parsing, mapping, and domain rules as pure logic.
- `View`: test rendering and interaction wiring only; avoid business assertions.
- Prefer dependency injection in `ViewModel` so side effects can be mocked.
- Keep tests focused on one layer at a time to preserve MVVM boundaries.
