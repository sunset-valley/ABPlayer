# Task Plan: Transcript Current Cue Through Gaps

## Implementation Plan

1. Locate current-cue tracking for the transcription/transcript reading area and confirm it is separate from the video subtitle overlay.
2. Characterize existing behavior before the first cue, inside a cue, between cues, and after playback end.
3. Update transcript current-cue behavior so cue gaps retain the latest cue that has already started.
4. Preserve transition behavior when playback reaches the next cue start time.
5. Preserve existing end-of-playback state handling while stopping further advancement.
6. Add focused tests for cue gaps, next-cue transitions, before-first-cue behavior, and playback end.

## Verification Plan

- Test playback time inside cue A selects cue A.
- Test playback time between cue A and cue B keeps cue A selected.
- Test playback time at cue B start selects cue B.
- Test playback time before the first cue does not select a future cue.
- Test playback end behavior matches existing transcript state expectations.
- Manually verify the video subtitle overlay is unchanged.

## Risks / Open Questions

- Existing transcript and subtitle overlay code may share helper logic; changes must avoid altering overlay behavior.
- End-of-playback behavior may need clarification if current code has inconsistent clear-versus-retain behavior.
- Tests should use deterministic cue timings to avoid boundary ambiguity.

## Progress Log

- 2026-04-22: Created plan from playback study roadmap P2.
