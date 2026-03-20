# Method-Level Cleanup Playbook

## Summary

This playbook defines the repeatable workflow used in this repository for method-level cleanup without functional changes. It focuses on reducing thin wrappers, deduplicating local logic, and preserving behavior through mandatory build and test verification.

## Details

### Prerequisites

1. The task is non-functional refactor only (no product behavior changes).
2. You can run repository-standard verification commands:
   - `xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayer -destination 'platform=macOS' build 2>&1 | tail -20`
   - `tuist test`
3. A current handoff note exists in `Docs/knowledge-mem-exchange/` for in-place updates.

### Step-by-Step Workflow

1. Identify high-confidence thin wrappers and duplicated blocks in view models first.
2. Remove wrappers only when call sites remain equally or more readable.
3. Prefer extracting small helpers when they reduce branch duplication inside a method.
4. Reuse existing fetch/helpers before adding new query code paths.
5. Keep retained one-hit APIs that are intentional architectural seams.
6. After each small batch, run build + full test suite.
7. Update the active `knowledge-mem-exchange` checkpoint in place (do not append historical logs).

### Guardrails

1. Do not remove APIs that may be used dynamically (runtime/selector/dynamic dispatch) without explicit verification.
2. Do not change persistence semantics while refactoring key handling.
3. Do not bundle large unrelated cleanup sets in one batch; keep changes small and reversible.
4. If readability worsens after wrapper removal, revert that specific micro-change and keep the wrapper.

### Expected Output

1. Smaller view-model API surfaces with fewer pass-through methods.
2. Reduced local duplication via helper extraction in complex methods.
3. Green build + tests after each cleanup batch.
4. Updated checkpoint doc describing only the latest completed batch and next actions.

## Related Docs

- [Method-level cleanup checkpoint](../knowledge-mem-exchange/0003_method-level-cleanup.md)
- [Project structure](../knowledge-graph/0001_project-structure.md)
- [Workflow rule](../../.agent/rules/workflow.md)
