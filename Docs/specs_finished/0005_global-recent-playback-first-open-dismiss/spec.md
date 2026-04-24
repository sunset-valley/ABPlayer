# Task Spec: Global Recent Playback First-Open Dismiss

## Summary

The global Recent Playback popover should remain presented on the first open, including when no recent items have been loaded yet. Users should not need to click the toolbar button a second time just to keep the popover open long enough to view its empty or loading state.

## Scope

- The toolbar-triggered global Recent Playback popover open flow.
- First-open behavior when the recent-items list is empty or has not yet been loaded.
- User-visible loading and empty states shown inside the popover.
- Focused regression coverage for the first-open presentation flow.

## Non-Goals

- Redesigning the Recent Playback toolbar button, popover layout, or menu contents.
- Changing how recent items are grouped, sorted, or played.
- Adding live refresh behavior while the popover is already open.
- Changing unrelated popover or sheet presentation behavior elsewhere in the app.

## Requirements

- Clicking the global Recent Playback toolbar button presents the popover on the first attempt.
- On the first open, the popover must remain visible while recent items are being loaded.
- If there are no recent items, the popover must remain visible long enough for the user to see the empty state.
- The popover must not automatically dismiss itself solely because the initial load updates observed state.
- Existing behavior for loading, empty, and populated content remains user-visible and functional.
- Existing play action behavior from the popover remains unchanged.
- This task treats the issue as an unintended dismiss/presentation bug, not as a crash-handling task.

## Constraints

- Keep the fix minimal and limited to the presentation bug.
- Preserve lazy loading on open unless investigation shows that lazy loading itself must change to satisfy the acceptance criteria.
- Do not change recent-item selection rules, grouping rules, or playback semantics as part of this task.
- The solution must work in the macOS SwiftUI toolbar context used by the main app window.

## Acceptance Criteria

- The first click on the global Recent Playback toolbar button keeps the popover open.
- With no available recent items, the first open shows the empty state instead of immediately dismissing.
- While the initial load is in progress, the first open shows the loading state without dismissing.
- With available recent items, the first open stays open and shows the loaded content.
- Users no longer need a second click to keep the popover open.
- Focused tests or reproducible verification steps cover the first-open presentation flow.

## Related Docs

- [Recently Played And Sidebar Progress](../0002_continue-watching-history-progress/spec.md)
- [Documentation rules](../../../.agent/rules/doc.md)
- [Workflow rules](../../../.agent/rules/workflow.md)
