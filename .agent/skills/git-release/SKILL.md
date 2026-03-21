# git-release

## Description

Prepares a new version for CI deployment: increments build version, updates changelog, creates a release commit, pushes a release branch, opens a PR with auto-merge, then switches back to the original branch.

## When

Run this skill when the user says:

- release X.Y.Z
- release
- `发布 X.Y.Z`, `发布X.Y.Z`
- `发布` (without version — auto-increment build number only)

Do not auto-trigger for general release discussions.

## Instructions

### Step 1: Preflight

1. Record the current branch: `ORIGINAL_BRANCH=$(git branch --show-current)`.
2. Check working tree is clean: `git status --porcelain`. If dirty, stop and ask the user.
3. Check tools: `git --version && gh --version`.
4. Pull latest: `git pull --ff-only`. If this fails (diverged history), stop and report.

### Step 2: Run the release script

```bash
./scripts/release.sh [version]
```

- Pass the user-specified version (e.g., `0.2.15`) as the argument. If the user didn't specify a version, run without arguments to auto-increment the build number.
- The script updates `Project.swift` (version strings), generates `CHANGELOG.md` entry, updates `.release_state`, and creates a local commit with message `ci(release_sh): <shortVersion>-<build>`.
- If the script fails, stop and report the error.

### Step 3: Extract the version from the commit

```bash
VERSION=$(git log -1 --pretty=%s | sed 's/ci(release_sh): //')
```

This gives a string like `0.2.15-94`.

### Step 4: Create release branch and push

```bash
git checkout -b "release/$VERSION"
git push -u origin "release/$VERSION"
```

### Step 5: Create PR and enable auto-merge

```bash
gh pr create --title "ci(release_sh): $VERSION" --body "Release $VERSION"
gh pr merge --auto --merge
```

If `gh pr merge --auto` fails, wait 3 seconds and retry once.

### Step 6: Switch back to original branch

```bash
git checkout "$ORIGINAL_BRANCH"
```

### Step 7: Output summary

Print: the version released, the PR URL, and confirm the branch is back to `ORIGINAL_BRANCH`.

### Failure Handling

- On any failure after Step 1, always attempt `git checkout "$ORIGINAL_BRANCH"` before stopping.
- Print which step failed and the error message.
