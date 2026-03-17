# git-release

## Description

Prepares a new version for CI deployment: increments build version, updates changelog, and creates a release commit. Triggers the CI pipeline which handles the actual GitHub Release creation.

## When

Run this skill when the user says:

- `git release`
- `/git-release`

Do not auto-trigger for general release discussions.

## Instructions

Run the release preparation script:

`./scripts/release.sh [version]`

### Arguments

- `version` (optional): Specify exact version (for example, `1.0.0`). If omitted, increments the build version automatically (for example, `0.2.9-48 -> 0.2.9-49`).

### Process

1. Run preflight checks:
   - Capture the current branch as `ORIGINAL_BRANCH`.
   - Ensure git working tree is clean before continuing.
   - Ensure required tools are available (`git`, `gh`).
2. Update codebase with `git pull --ff-only`.
3. Update `Project.swift` (increment `buildVersionString` or set new `shortVersionString`).
4. Generate a new `CHANGELOG.md` entry from recent commits.
5. Run quality gates before creating release commit:
   - Build succeeds.
   - Tests succeed (or explicitly report why they were skipped).
6. Create a local git commit with message format `ci(scope): MESSAGE` without `Ultraworked with` and `Co-authored-by`.
7. Create a branch name based on current commits and push it.
8. Create a PR.
9. Enable auto-merge of the PR using `gh pr merge <CURRENT PR> --auto --merge`.
   - If it fails due to timing/state, retry with short backoff and clear error output.
10. Switch branch back to `ORIGINAL_BRANCH`.
11. Output summary.

### Failure Handling

- On any failure, stop immediately with non-zero exit code.
- Always attempt to switch back to `ORIGINAL_BRANCH` before exiting.
- Print a concise failure reason and the failed step.
