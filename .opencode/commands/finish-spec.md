---
description: Move completed spec to Docs/specs_finished by numeric prefix
model: selfhost/gpt-5.4-mini
---

Run the repository helper to archive a completed spec.

Requirements:

- Accept exactly one numeric argument from command arguments.
- Match the spec directory whose name starts with that numeric value (for example: `12` matches `0012_*`).
- If the argument is missing or invalid, return a short usage message: `/finish-spec 12`.

Execute:
!`./scripts/finish-spec.sh $ARGUMENTS`

After execution, report concise outcome:

- success: show source and destination paths from script output
- failure: show the script error only
