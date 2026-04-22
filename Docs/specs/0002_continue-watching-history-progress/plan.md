# Task Plan: Continue Watching, History, And Sidebar Progress

## Implementation Plan

1. Locate the current playback history source, folder browsing flow, sidebar file-row rendering, and global Continue Watching menu behavior.
2. Define the current-folder latest unfinished item using existing playback history semantics.
3. Add progress visibility for file rows with valid position and duration.
4. Add current-folder Continue Watching display above the file list.
5. Adjust folder file ordering so recently played files appear first while preserving existing ordering for unplayed files.
6. Update global Continue Watching grouping so each directory contributes only its latest played unfinished item.
7. Preserve completed-file filtering behavior and add focused tests for the changed sorting, grouping, and progress rules.

## Verification Plan

- Test sidebar progress visibility for valid progress, missing progress, zero duration, and invalid duration.
- Test current-folder Continue Watching selection uses the latest unfinished file.
- Test recently played files appear before unplayed files.
- Test unplayed files preserve the existing sort order.
- Test global Continue Watching groups to one latest-played item per directory.
- Test completed-file filtering remains unchanged.
- Manually verify the sidebar and current-folder card with a small folder containing mixed played, unplayed, and completed files.

## Risks / Open Questions

- Existing history records may not have cached duration for every media file.
- Sorting rules may need stable tie-breaking when several files have similar playback timestamps.
- Completed-file filtering behavior must be identified before changing the global Continue Watching query.

## Progress Log

- 2026-04-22: Created plan from playback study roadmap P1.
