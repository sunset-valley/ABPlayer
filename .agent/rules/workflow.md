---
trigger: model_decision
description: Collaboration and workflow rules
---

# Workflow

- Before starting any development task that changes Swift source, tests, build configuration, app behavior, or user-visible behavior, create or update a task directory under `Docs/specs/NNNN_short-topic/`.
- Each task directory must contain `spec.md` for goal constraints and `plan.md` for execution planning.
- Do not implement before `spec.md` captures goal, scope, non-goals, and acceptance criteria, and `plan.md` captures the implementation and verification plan.
- Keep task specs goal-oriented: constrain outcomes and verification, not implementation details, unless the user explicitly requires a specific approach.
- Keep implementation details in `plan.md`, not `spec.md`.
- If requirements are ambiguous, clarify or record assumptions in `spec.md` before coding.
- Keep `spec.md` and `plan.md` updated when scope or execution changes during implementation.
- Documentation-only, rule-only, formatting-only, and exploratory read-only tasks do not require a task spec unless they lead to implementation.
- Ask for clarification when requirements are ambiguous.
- When trade-offs matter, provide 2-3 concrete options.
- During feature development or bug fixing, run only the tests related to the changed scope.
- Run the full test suite only before a release (or when explicitly requested).

# Quick Commit Convention

- If the user says `quick commit`, generate a commit message from:
  - `git status`
  - `git diff --staged`
  - `git log -n 3`
- Message format: `type(scope): message`
