# Task Plan: Transcript Current Cue Through Gaps

## Implementation Plan

1. Confirm the current cue responsibilities before changing code.
    - `SubtitleViewModel.updateCurrentCue(time:cues:)` and playback tracking currently drive the transcript active cue.
    - `VideoPlayerViewModel.updateCurrentSubtitle(at:)` uses the same cue lookup for the video subtitle overlay and must keep range-based overlay behavior.
    - `TranscriptTextView` only consumes `activeCueID`; it should not need behavior changes unless the active ID contract changes.
    - This task may only change transcript current-cue highlighting; previous/next sentence navigation and seek target calculation are out of scope.

2. Separate transcript cue tracking from video subtitle overlay lookup.
    - Keep `findActiveCue(at:epsilon:)` as the overlay-safe lookup that only returns a cue while playback time is inside the cue range.
    - Add or reuse a transcript-specific lookup that returns the latest cue whose `startTime` is at or before playback time, while returning `nil` before the first cue.
    - Preserve sorted-by-`startTime` assumptions and binary-search behavior for cue lookup.
    - Name the transcript-specific lookup around "latest started cue" rather than "active cue" to avoid future misuse.
    - Keep `activeCueIndex(at:)`, `previousSentenceStart(at:)`, and `nextSentenceStart(at:)` unchanged because they drive sentence navigation.

3. Update transcript current-cue paths.
    - Change `SubtitleViewModel.updateCurrentCue(time:cues:)` to use the transcript-specific lookup.
    - Change the private playback observer path used by `trackPlayback(cues:)` to use the same transcript-specific lookup.
    - Preserve the `scrollState.isUserScrolling` guard so manual transcript scrolling still freezes active-cue updates.
    - Preserve reset, empty-cue, invalid-time, and no-player behavior.

4. Keep video subtitle overlay behavior unchanged.
    - Leave `VideoPlayerViewModel.updateCurrentSubtitle(at:)` using `findActiveCue(at:)`.
    - Do not change subtitle parsing, cue timing, or overlay display state.
    - Do not change previous/next sentence behavior or seek target calculation.

5. Add focused coverage.
    - Extend `SubtitleViewModelTests` with gap, boundary, before-first-cue, and after-last-cue cases.
    - Add model/helper tests if the transcript-specific lookup is implemented in the `SubtitleCue` array extension.
    - Keep tests focused on current-cue selection instead of transcript rendering.

## Verification Plan

- Automated tests:
    - `SubtitleViewModel.updateCurrentCue` returns `nil` before the first cue starts.
    - During a gap after cue A ends and before cue B starts, `currentCueID` remains cue A.
    - At cue B's start time, `currentCueID` changes to cue B.
    - After the last cue ends, `currentCueID` remains the last cue.
    - Existing user-scroll freeze behavior still keeps the previous `currentCueID`.
    - Video subtitle coverage confirms overlay text is range-based, including `nil` during gaps between cues.
    - Previous/next sentence coverage confirms navigation still seeks to the same cue start times as before, including when playback time is in a gap.

- Manual checks:
    - Open a transcription with visible cue gaps and play through a gap; the transcript highlight stays on the previous sentence.
    - Continue into the next cue; the transcript highlight advances at the next cue start.
    - Seek before the first cue; no future transcript sentence becomes active.
    - Let playback pass the final cue; the transcript remains on the final started cue.
    - Confirm the video subtitle overlay still disappears in gaps and does not show the previous cue.
    - Confirm previous/next sentence controls behave the same as before from a gap.

- Commands:
    - Run the focused test target through `tuist test` with the smallest available filter for `SubtitleViewModelTests` and related subtitle lookup tests.
    - Run the project build command if implementation touches shared subtitle model code or if filtered test execution does not compile all affected files.

- Intentionally skipped coverage:
    - No UI snapshot coverage unless the active-cue rendering changes; this task changes selection semantics, not transcript layout.
    - No subtitle parser coverage because parsed cue timing is out of scope.
    - No full test suite unless requested or the focused tests reveal broader coupling.

## Risks / Open Questions

- Risk: `findActiveCue(at:)` is shared by transcript and video overlay. Changing it directly would make the overlay keep showing old subtitles through gaps, which violates the spec.
- Risk: `activeCueIndex(at:)`, `previousSentenceStart(at:)`, and `nextSentenceStart(at:)` are used by sentence navigation. Repurposing them for transcript gap retention would change previous/next behavior outside this task.
- Risk: Current cue lookup assumes cues are sorted by `startTime`. If any transcription path can provide unsorted cues, the binary-search result could be wrong; this task should not broaden into sorting unless a failing test exposes it.
- Risk: Epsilon handling near cue starts can select the next cue slightly early. The transcript behavior should match existing timing tolerance unless acceptance criteria require exact boundary behavior.
- Risk: Manual scroll state intentionally freezes active-cue tracking. Gap retention should not resume or override user-scroll pause.
- Risk: Retaining the last cue after playback end must not retain stale cue IDs across track changes, subtitle reloads, reset, or empty cue lists.
- Risk: Playback tracking calls cue lookup frequently, so the transcript-specific lookup should keep binary-search behavior and avoid per-tick linear scans over all cues.
- Risk: Ambiguous "active cue" naming may cause future callers to use the wrong lookup. The transcript helper should use "latest started cue" terminology.

## Defaults

- Use the same `0.001` second epsilon as existing active-cue detection for transcript cue retention.
- If two cues share the same `startTime`, select the later cue in array order to match the current binary-search candidate behavior.
- Direct cue taps continue setting `currentCueID` immediately because the user explicitly selected that cue and the UI should respond immediately.

## Progress Log

- 2026-04-22: Created plan from playback study roadmap P2.
- 2026-04-24: Reworked plan into implementation, verification, and risk/open-question sections with concrete code and test touchpoints.
- 2026-04-25: Added transcript-only scope constraints, sentence-navigation exclusions, overlay/navigation verification, and default decisions.
- 2026-04-25: Implemented transcript latest-started cue lookup, updated transcript current-cue tracking, added focused unit coverage, and verified focused tests plus macOS build.
