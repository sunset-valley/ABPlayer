# Task Spec: Transcript Current Cue Through Gaps

## Summary

The transcript reading area should keep the previous sentence selected during gaps between subtitle cues. This keeps the current sentence stable for study and reading until the next cue begins or playback ends.

## Scope

- Current-cue tracking in the transcription/transcript reading area.
- Behavior during gaps between subtitle cues.
- Transition to the next cue when playback reaches that cue.
- End-of-playback behavior for transcript current-cue state.

## Non-Goals

- Changing the video subtitle overlay.
- Changing subtitle parsing or cue timing data.
- Redesigning transcript scrolling, selection, or annotation behavior outside current-cue tracking.
- Adding new playback modes.

## Requirements

- When playback is between two cues, the transcript keeps the latest cue that has already started as the current cue.
- When playback reaches the next cue start time, the transcript switches to that next cue.
- At playback end, the transcript current cue stays on the last cue that has already started.
- The video subtitle overlay behavior is unchanged.

## Constraints

- This behavior applies only to the transcription/transcript reading area.
- Playback end should preserve the last started cue as the transcript current cue for consistent gap handling.
- The solution should handle cue gaps without introducing incorrect cue selection before the first cue.
- Do not prescribe current-cue algorithm or ViewModel structure in this spec; implementation details belong in `plan.md`.

## Acceptance Criteria

- During a gap after cue A and before cue B, the transcript current cue remains cue A.
- At cue B's start time, the transcript current cue changes to cue B.
- Before the first cue, the transcript does not incorrectly select a future cue.
- Playback end leaves the transcript current cue on the last cue that has already started.
- Video subtitle overlay behavior is unchanged.
- Focused coverage verifies cue gaps, next-cue transitions, and playback-end handling.

## Related Docs

- [Playback Study Roadmap](../../knowledge-mem-exchange/0004_playback-study-roadmap.md)
- [Transcript scroll state](../../knowledge-graph/0004_transcript-scroll-state.md)
- [Documentation rules](../../../.agent/rules/doc.md)
- [Workflow rules](../../../.agent/rules/workflow.md)
