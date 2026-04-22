# Task Spec: Minimal Repeat-After-Me Training

## Summary

Users should be able to practice subtitle sentences in a minimal repeat-after-me training mode. The first version plays each subtitle sentence a configurable number of times with a configurable pause between repeats.

## Scope

- Sentence-based training using subtitle cue start and end times.
- User-configurable per-sentence repeat count.
- Default repeat count of 3.
- User-configurable pause mode and pause length.
- Fixed-duration pause mode.
- Sentence-duration-ratio pause mode.
- Start, stop, and exit behavior for training mode.

## Non-Goals

- Recording the user's voice.
- Automatic language-based playback speed.
- Free-form 3/5/7/9-second pause modes.
- Showing subtitles only on the last repeat.
- Slow-normal-fast progressive training.
- Full training analytics or scoring.

## Requirements

- Users can configure how many times each sentence repeats.
- The default per-sentence repeat count is 3.
- Users can configure pause mode and pause length.
- Training plays sentence by sentence using subtitle cue start and end times.
- Each sentence replays according to the configured repeat count.
- Fixed-duration pause mode pauses for the configured number of seconds.
- Sentence-duration-ratio pause mode pauses for a configured percentage of the current sentence duration.
- Users can start, stop, and exit training mode.

## Constraints

- The first version should stay minimal and sentence-cue based.
- Deferred training modes should remain out of scope even if they appear in related backlog notes.
- Pause behavior should be predictable for very short and very long subtitle cues.
- Training mode should not permanently change normal playback behavior after exit.
- Do not prescribe state model, settings storage, or UI layout in this spec; implementation details belong in `plan.md`.

## Acceptance Criteria

- A user can start repeat-after-me training from an appropriate playback context.
- Each subtitle sentence plays from cue start to cue end.
- Each sentence repeats the configured number of times.
- Repeat count defaults to 3 until changed.
- Fixed-duration pause mode waits the configured number of seconds between repeats.
- Sentence-ratio pause mode waits based on the current sentence duration.
- A user can stop or exit training and return to normal playback behavior.
- Deferred features are not implemented as part of this task.

## Related Docs

- [Playback Study Roadmap](../../knowledge-mem-exchange/0004_playback-study-roadmap.md)
- [Project structure](../../knowledge-graph/0001_project-structure.md)
- [Documentation rules](../../../.agent/rules/doc.md)
- [Workflow rules](../../../.agent/rules/workflow.md)
