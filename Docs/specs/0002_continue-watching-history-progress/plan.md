# Task Plan: Recently Played And Sidebar Progress

## Implementation Plan

1. Rename the existing `Continue Watching` feature surface to `Recently Played`, including user-visible copy, view-model state, helper types, and focused test names.
2. Refactor `FolderNavigationViewModel` so current-folder and global recent-item selection share one directory-based selection rule.
3. Keep `Recently Played` eligibility based on playback history presence, valid relative path, and file existence on disk; do not exclude completed files from the card or global menu.
4. Group global `Recently Played` results to at most one file per directory, using the most recently played file for that directory and applying the display limit after grouping.
5. Keep current-folder `Recently Played` resolution limited to the files in the open folder and return that folder's most recently played file.
6. Add sidebar file-row progress rendering that appears only when playback position is positive and cached duration is valid and positive, without changing file ordering.
7. Preserve existing click behavior for recent items: navigate to the file, rebuild or sync the queue, and autoplay from the saved position.
8. Update focused tests to cover current-folder card visibility, inclusion of completed recent items, per-directory grouping, invalid-entry filtering, sidebar progress visibility, and unchanged file ordering.

## Verification Plan

- Run focused tests covering `FolderNavigationViewModel` recent-item selection and refresh behavior.
- Run focused tests covering row-progress visibility and playback/navigation behavior for recent items.
- Manually verify a folder with mixed unplayed, in-progress, and completed files:
  - the current-folder `Recently Played` card appears only when playback history exists
  - the card and global menu point to the same latest file for that directory
  - sidebar progress bars appear only when both position and duration are valid
  - file-list ordering stays unchanged

## Risks / Open Questions

- Existing records may have `lastPlayedAt` without a valid cached duration; card/menu should still work while row progress remains hidden.
- Directory grouping must handle root-level library files consistently so they collapse into a single library bucket.
- The current playback action resumes from saved position even for completed items; this is intentional for this task and should not be “fixed” opportunistically.

## Progress Log

- 2026-04-23: Replaced the outdated Continue Watching plan with a Recently Played plan aligned to the updated spec.
