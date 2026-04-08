---
trigger: model_decision
description: Collaboration and workflow rules
---

# Workflow

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
