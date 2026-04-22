---
description: Move completed spec to Docs/specs_finished by 4-digit ID
model: selfhost/gpt-5.4-mini
---

Run the repository helper to archive a completed spec.

Requirements:
- Accept exactly one 4-digit spec ID from command arguments.
- If the argument is missing or invalid, return a short usage message: `/finish-spec 0001`.

Execute:
!`./scripts/finish-spec.sh $ARGUMENTS`

After execution, report concise outcome:
- success: show source and destination paths from script output
- failure: show the script error only
