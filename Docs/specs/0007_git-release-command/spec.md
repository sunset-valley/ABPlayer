# Task Spec: Git Release Command

## Summary

Convert the repository-local `git-release` automation instructions from a skill into an OpenCode local command so release preparation is invoked explicitly through the command system.

## Scope

- Preserve the existing release workflow behavior, including preflight checks, release script execution, branch creation, PR creation, auto-merge setup, and returning to the original branch.
- Make the command discoverable under `.opencode/commands`.
- Remove the repository-local skill entry so `git-release` is no longer represented as a skill.

## Non-Goals

- Changing the release script behavior.
- Running an actual release.
- Changing Swift source, tests, build settings, or app behavior.

## Requirements

- The command must support an optional version argument.
- The command must document the clean-working-tree preflight requirement.
- The command must retain failure handling that attempts to switch back to the original branch.
- The command must report the released version, PR URL, and final branch.

## Constraints

- Documentation must remain in English.
- The migration must stay scoped to repository-local agent assets and the required task spec.

## Acceptance Criteria

- `.opencode/commands/git-release.md` exists and contains the release workflow.
- `.agent/skills/git-release/SKILL.md` is removed.
- The command instructions are equivalent to the previous skill behavior.
- No application source files are changed.

## Related Docs

- [Documentation rules](../../../.agent/rules/doc.md)
- [Workflow rules](../../../.agent/rules/workflow.md)
