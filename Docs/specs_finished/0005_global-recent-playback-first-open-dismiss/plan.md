# Task Plan: Global Recent Playback First-Open Dismiss

## Implementation Plan

1. Confirm the first-open dismiss path in the toolbar popover flow, including which observed state changes occur during the initial lazy load.
2. Identify the smallest stable presentation-state ownership needed so the popover can stay presented across the initial load.
3. Update the Recent Playback toolbar flow so first-open loading and empty states can remain visible without requiring a second click.
4. Keep the existing lazy-load-on-open behavior unless a smaller and safer alternative is required by the bug fix.
5. Preserve existing play-item behavior and existing content rendering for loading, empty, and populated states.
6. Add or update focused regression coverage for first-open presentation behavior, including the no-data path.

## Implementation Notes

- Use parent-owned presentation state for the toolbar popover (`MainSplitView` / demo host view), and keep `RecentlyPlayedToolbarMenuView` content-only.
- Trigger lazy loading from the parent `showRecentlyPlayed` state transition to `true`.
- Keep existing content rendering and play action behavior unchanged; selecting an item should still close the popover.

## Verification Plan

- Run focused tests covering the global Recent Playback popover first-open flow.
- Add or update a UI-level regression check that verifies the first click keeps the popover presented.
- Manually verify:
  - first open with no recent items stays visible and shows the empty state
  - first open during loading stays visible and shows the loading state
  - first open with recent items stays visible and shows content
  - item playback from the popover still works as before
- If automated coverage for macOS popover persistence is limited, document the manual verification gap explicitly.

## Risks / Open Questions

- SwiftUI toolbar presentation state may be sensitive to view identity changes during observed-state updates.
- The current issue may be reproducible only for the initial uncached load path; verification should explicitly cover both cold and warm states.
- UI tests may need a deterministic demo or fixture setup for the no-data first-open scenario if current coverage only exercises populated data.

## Progress Log

- 2026-04-23: Created spec and plan for the global Recent Playback first-open dismiss bug.
- 2026-04-23: Recorded the user clarification that the symptom is an unintended dismiss, not a crash.
- 2026-04-24: Confirmed implementation direction with user: move popover presentation state out of `RecentlyPlayedToolbarMenuView` and into parent views.
- 2026-04-24: Aligned UI test demo with production structure by moving the Recently Played trigger into the demo view toolbar.
- 2026-04-24: Fixed demo setup timing regression after toolbar migration by guarding one-time async setup with an in-progress state and completion marker after setup returns.
- 2026-04-24: Updated UI regression assertion to verify toolbar popover presentation state via deterministic demo metric, avoiding flaky direct lookup of popover content nodes in macOS UI automation.
