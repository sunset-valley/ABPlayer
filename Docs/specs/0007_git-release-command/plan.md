# Task Plan: Git Release Command

## Implementation Plan

1. Read the existing `git-release` skill.
2. Create an OpenCode local command that preserves the release workflow and optional version argument.
3. Remove the old repository-local skill file.
4. Verify the resulting file tree and diff.

## Verification Plan

- Inspect the new command file for parity with the old skill.
- Run `git status --short` and review the diff.
- Skip build and tests because this task changes only agent workflow documentation.

## Risks / Open Questions

- The repository contains `.opencode/commands/finish-spec.md`, so the command follows that frontmatter markdown format.

## Progress Log

- 2026-04-24: Created plan.
- 2026-04-24: Added local command and prepared skill removal.
- 2026-04-24: Verified the changed file tree and skipped app build/tests because only agent workflow docs changed.
- 2026-04-24: Moved the command definition to `.opencode/commands` after correcting the target command system.
