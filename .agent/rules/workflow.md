---
trigger: model_decision
description: Collaboration and workflow rules
---

# Workflow

- Ask for clarification when requirements are ambiguous.
- When trade-offs matter, provide 2-3 concrete options.

# Quick Commit Convention

- If the user says `quick commit`, generate a commit message from:
  - `git status`
  - `git diff --staged`
  - `git log -n 3`
- Message format: `type(scope): message`
