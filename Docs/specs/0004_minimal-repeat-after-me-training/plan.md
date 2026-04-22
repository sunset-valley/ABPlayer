# Task Plan: Minimal Repeat-After-Me Training

## Implementation Plan

1. Locate playback control, subtitle cue timing, settings, and any existing mode-management patterns.
2. Define the minimal sentence-drill execution state after reviewing current playback architecture.
3. Add repeat count and pause configuration using existing settings patterns.
4. Add cue-based sentence playback that repeats each cue according to the configured repeat count.
5. Add fixed-duration pause behavior.
6. Add sentence-duration-ratio pause behavior.
7. Add start, stop, and exit flows that restore normal playback behavior.
8. Add focused tests for repeat counts, pause calculations, cue transitions, and exit behavior where feasible.

## Verification Plan

- Test default repeat count is 3.
- Test custom repeat count controls how many times a sentence plays.
- Test fixed-duration pause uses the configured seconds.
- Test sentence-ratio pause uses the current cue duration.
- Test start, stop, and exit behavior.
- Manually verify training with short cues, long cues, and normal playback after exit.
- Confirm deferred features are not exposed in the first version.

## Risks / Open Questions

- Subtitle cue boundaries may need guardrails for missing or overlapping cue timings.
- Existing playback controls may need clear ownership rules while training mode is active.
- Settings UI scope should stay minimal to avoid turning this into a larger training redesign.
- Very short cues may need a minimum practical pause duration; this should be decided during implementation if needed.

## Progress Log

- 2026-04-22: Created plan from playback study roadmap P3.
