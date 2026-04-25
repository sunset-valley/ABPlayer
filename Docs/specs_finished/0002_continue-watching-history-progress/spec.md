# Task Spec: Recently Played And Sidebar Progress

## Summary

Folder browsing should make recent playback easier to find. If a folder has playback history, the UI should show that folder's most recently played file, display per-file progress when valid progress exists, and expose one recent item per directory in the global Recently Played menu.

## Scope

- Current-folder `Recently Played` card.
- Sidebar file-row playback progress display.
- Global `Recently Played` menu grouped by directory.

## Non-Goals

- Redesigning the full sidebar layout.
- Redesigning playback history storage; only minimal persistence changes needed for the specified UI behavior are in scope.
- Adding cloud sync or cross-device history.
- Changing file-list ordering.

## Requirements

- Opening a folder shows one current-folder `Recently Played` card only if that folder has at least one playback record.
- If the current folder has no playback records, no `Recently Played` card is shown.
- The current-folder `Recently Played` card points to the most recently played file in that folder, even if that file is complete.
- Progress is based on current playback position divided by cached duration.
- File rows show a progress bar only when playback position is positive and cached duration is valid and positive.
- The global `Recently Played` menu shows at most one item per directory.
- For each directory, the global `Recently Played` menu and the current-folder card use the same selection rule: that directory's most recently played file.
- Playback history affects card, menu, and progress display only. It does not change file-list ordering.
- After playback starts for a file in the current folder, the current-folder `Recently Played` card updates to that file's latest playback record without requiring folder navigation.
- In `Recently Played` surfaces (current-folder card and global menu), the actively playing item displays `Now Playing` in the bottom metadata area and hides the progress bar while playback is active.
- The global `Recently Played` menu remains lazily refreshed when loaded by the existing menu open flow; this task does not add live auto-refresh while the menu is already presented.

## Constraints

- Progress display must not show misleading values when duration is missing or invalid.
- File-list ordering must remain unchanged.
- This spec does not prescribe data-model or UI component structure. Implementation details belong in `plan.md`.

## Acceptance Criteria

- A folder with playback history shows a `Recently Played` card above the file list.
- A folder with no playback history shows no `Recently Played` card.
- The card points to that folder's most recently played file, including a completed file when it is the most recently played file.
- File rows show a progress bar only when playback position and cached duration are both valid.
- The global menu shows at most one item per directory.
- Opening a directory shown in the global menu shows the same file in the current-folder card.
- Starting playback in the current folder updates the current-folder `Recently Played` card to that file without requiring folder switches.
- While an item is actively playing, both the current-folder card and global menu row show `Now Playing` in the bottom metadata area and do not show a progress bar for that item.
- File-list ordering is unchanged.

## Related Docs

- [Playback Study Roadmap](../../knowledge-mem-exchange/0004_playback-study-roadmap.md)
- [Project structure](../../knowledge-graph/0001_project-structure.md)
- [Documentation rules](../../../.agent/rules/doc.md)
- [Workflow rules](../../../.agent/rules/workflow.md)
