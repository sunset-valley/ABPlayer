# Task Spec: Continue Watching, History, And Sidebar Progress

## Summary

Folder browsing should make playback history easier to trust and resume. When a folder has unfinished playback, users should see the latest unfinished item clearly, each file with valid progress should show that progress, and recently played files should be easier to find.

## Scope

- Current-folder Continue Watching card.
- Sidebar file-row playback progress display.
- Recently played ordering within a folder.
- Global Continue Watching menu grouping by directory.
- Completed-file filtering behavior that already exists.

## Non-Goals

- Redesigning the full sidebar layout.
- Changing playback history persistence beyond what is required for the visible behavior.
- Adding cloud sync or cross-device history.
- Changing playback completion rules unless needed to preserve existing behavior.

## Requirements

- Entering a folder with unfinished playback history shows a Continue Watching card above the file list.
- The current-folder Continue Watching card shows the latest played unfinished file in that folder.
- File rows with valid playback progress show a progress bar.
- Progress is based on current playback position divided by cached duration.
- The progress bar is hidden when a file has no playback progress or no valid duration.
- Recently played files appear before files without playback records.
- Files without playback records continue using the existing sort behavior.
- The global Continue Watching menu shows one latest-played item per directory.
- Completed-file filtering behavior is preserved.

## Constraints

- Progress display must avoid showing misleading values when duration is missing or invalid.
- Existing sort behavior for files without playback records must remain stable.
- Current-folder and global Continue Watching behavior should be consistent but not duplicate multiple files from the same directory in the global menu.
- Do not prescribe data-model or UI component structure in this spec; implementation details belong in `plan.md`.

## Acceptance Criteria

- Opening a folder with unfinished history shows one current-folder Continue Watching card.
- The card points to the latest played unfinished file in that folder.
- Sidebar rows show progress only for files with valid progress and valid duration.
- Recently played files sort above unplayed files without disrupting the existing unplayed-file order.
- The global Continue Watching menu contains at most one item per directory, using that directory's latest played unfinished file.
- Completed files remain filtered according to the existing behavior.
- Focused coverage verifies progress visibility, grouping, latest-played ordering, and completed-file filtering.

## Related Docs

- [Playback Study Roadmap](../../knowledge-mem-exchange/0004_playback-study-roadmap.md)
- [Project structure](../../knowledge-graph/0001_project-structure.md)
- [Documentation rules](../../../.agent/rules/doc.md)
- [Workflow rules](../../../.agent/rules/workflow.md)
