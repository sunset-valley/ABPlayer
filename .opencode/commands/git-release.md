---
description: Prepare a release branch and PR with an optional app version
model: selfhost/gpt-5.4-mini
---

Prepare a new version for CI deployment. Treat `$ARGUMENTS` as an optional short version such as `0.2.15`; if empty, let the release script auto-increment the build number.

Requirements:

- Record the original branch before making changes.
- Stop and ask the user if the working tree is dirty.
- Require `git` and `gh`.
- Pull with fast-forward only.
- Run `./scripts/release.sh $ARGUMENTS` when a version is supplied, or `./scripts/release.sh` when no version is supplied.
- The release script is expected to update `Project.swift`, generate a `CHANGELOG.md` entry, update `.release_state`, and create a local commit named `ci(release_sh): <shortVersion>-<build>`.
- Extract the release version from the last commit subject by removing the `ci(release_sh): ` prefix.
- Create and push `release/<version>`.
- Create a PR titled `ci(release_sh): <version>` with body `Release <version>`.
- Enable PR auto-merge with merge strategy. If this fails, wait 3 seconds and retry once.
- Always attempt to switch back to the original branch after any failure that happens after the original branch is recorded.
- Report the released version, PR URL, and final branch.

Use this exact workflow:

1. Record the current branch:

   ```bash
   ORIGINAL_BRANCH=$(git branch --show-current)
   ```

2. Verify the working tree is clean:

   ```bash
   git status --porcelain
   ```

3. Verify tools:

   ```bash
   git --version
   gh --version
   ```

4. Pull latest:

   ```bash
   git pull --ff-only
   ```

5. Run the release script:

   ```bash
   ./scripts/release.sh $ARGUMENTS
   ```

   If `$ARGUMENTS` is empty, run:

   ```bash
   ./scripts/release.sh
   ```

6. Extract the release version:

   ```bash
   VERSION=$(git log -1 --pretty=%s | sed 's/ci(release_sh): //')
   ```

7. Create and push the release branch:

   ```bash
   git checkout -b "release/$VERSION"
   git push -u origin "release/$VERSION"
   ```

8. Create the PR and enable auto-merge:

   ```bash
   PR_URL=$(gh pr create --title "ci(release_sh): $VERSION" --body "Release $VERSION")
   gh pr merge --auto --merge
   ```

9. Switch back to the original branch:

   ```bash
   git checkout "$ORIGINAL_BRANCH"
   ```

On failure, report the failed step and the command error only after attempting to return to `$ORIGINAL_BRANCH`.
