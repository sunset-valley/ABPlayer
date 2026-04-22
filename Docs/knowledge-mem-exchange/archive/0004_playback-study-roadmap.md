# Playback Study Roadmap

## Summary

The next playback work should improve the day-to-day study flow before adding larger training modes. The first milestone focuses on making video clicks feel responsive, making playback history easier to trust, keeping the transcript's current sentence stable between cues, and defining a small repeat-after-me training mode with configurable repeat and pause behavior.

## Details

### P0: Fix Video Tap Play/Pause Latency

Spec: [Video tap play/pause latency](../specs/0001_video-tap-play-pause-latency/spec.md)

Keep double-click fullscreen, but make single-click feedback feel immediate. A video-area click should show the Play/Pause HUD immediately, then delay the actual play/pause action by 180 ms so the app can detect whether a second click turns the gesture into fullscreen.

Expected behavior:

- Single-click video area: show the Play/Pause HUD immediately, then play or pause after 180 ms.
- Double-click video area: cancel the pending play/pause action and toggle fullscreen.
- The first click in a double-click sequence still gives immediate HUD feedback.
- If 180 ms creates too many accidental play/pause actions during slower double-clicks, retune the delay to 200-220 ms after testing.

TODO:

- [ ] Keep double-click fullscreen.
- [ ] Show the HUD immediately when the video area is clicked.
- [ ] Delay the single-click play/pause action by 180 ms.
- [ ] Cancel the pending play/pause action when a double-click is detected, then toggle fullscreen.
- [ ] Verify HUD timing and playback state no longer feel delayed.
- [ ] Add UI or ViewModel coverage if feasible.

### P1: Clean Continue Watching, Playback History, And Sidebar Progress

Spec: [Continue Watching, history, and sidebar progress](../specs/0002_continue-watching-history-progress/spec.md)

When entering a folder with unfinished playback history, show a Continue Watching card above the file list. The card should show the most recently played file in that folder. The sidebar file list should also show playback progress for each file with valid progress, and recently played files should appear at the top of the list.

Expected behavior:

- Entering a folder with an unfinished playback record shows Continue Watching at the top.
- Continue Watching shows the latest played file in the current folder.
- Each file row with valid playback progress shows a progress bar.
- Recently played files appear first; files without playback records continue using the current sort order.
- The global Continue Watching menu shows only one item per directory: the latest played file in that directory.

TODO:

- [ ] Show a playback progress bar in sidebar file rows.
- [ ] Calculate progress from `currentPlaybackPosition / cachedDuration`.
- [ ] Hide the progress bar when a file has no playback progress or no valid duration.
- [ ] Show a Continue Watching card after entering a folder when it has unfinished playback history.
- [ ] Make the current-folder Continue Watching card show the folder's latest played file.
- [ ] Sort recently played files to the top of the file list.
- [ ] Keep files without playback records under the existing sort behavior.
- [ ] Make the global Continue Watching menu show one latest-played file per directory.
- [ ] Preserve the completed-file filtering behavior.
- [ ] Add tests for sidebar progress, Continue Watching grouping, latest-played ordering, and completed-file filtering.

### P2: Keep The Transcript Current Sentence Until The Next Cue Or End

Spec: [Transcript current cue through gaps](../specs/0003_transcript-current-cue-gaps/spec.md)

This behavior applies to the transcription/transcript reading area only. It should not change the video subtitle overlay. When playback enters the gap between two subtitle cues, the transcript should keep the previous sentence as the current cue until the next cue starts. At playback end, the current cue should stop advancing or clear according to the existing transcript state handling.

TODO:

- [ ] Update the Transcription View current-cue tracking logic.
- [ ] When there is no active cue, fall back to the latest cue that has already started.
- [ ] Switch to the next cue when its start time is reached.
- [ ] Stop advancing the current cue at playback end.
- [ ] Do not change `VideoPlayerView` subtitle overlay behavior.
- [ ] Add tests for cue gaps, next-cue transitions, and end-of-playback behavior.

### P3: Minimal Repeat-After-Me Training

Spec: [Minimal repeat-after-me training](../specs/0004_minimal-repeat-after-me-training/spec.md)

Build the first training mode around subtitle sentences. Each sentence should play a configurable number of times, with a configurable pause between repeats. Repeat count is user-configurable in settings and defaults to 3.

Pause modes:

- Fixed duration: pause for N seconds between repeats.
- Sentence ratio: pause for a percentage of the current sentence duration.

Expected behavior:

- Users can configure repeat count in settings.
- The default repeat count is 3.
- Users can configure pause mode and pause length in settings.
- Training plays sentence by sentence using subtitle cue start and end times.
- Recording, automatic language-based playback speed, and free-form 3/5/7/9-second pause modes are deferred.

TODO:

- [ ] Design the Sentence Drill state model before adding UI.
- [ ] Add a repeat-after-me setting for per-sentence repeat count.
- [ ] Default per-sentence repeat count to 3.
- [ ] Support cue-based sentence start and end times.
- [ ] Replay each sentence according to the configured repeat count.
- [ ] Make the pause between repeats configurable.
- [ ] Support fixed-second pause configuration.
- [ ] Support sentence-duration-percentage pause configuration.
- [ ] Support start, stop, and exit for training mode.
- [ ] Defer recording, automatic language-speed behavior, and 3/5/7/9-second free-pause modes.

### Value Evaluation Backlog

These items need product-value evaluation, not code investigation. Decide whether each one is worth building and where it belongs in the roadmap.

- [ ] Decide whether the Playback menu should add play/pause, jump controls, subtitle toggle, or loop mode commands.
- [ ] Decide whether file selection should scroll the sidebar list to the top.
- [ ] Decide whether Chinese 2x and English 1x playback speed matches the main learning workflow.
- [ ] Decide whether auto-recording during repeat-after-me is worth the permission, storage, playback, and privacy complexity.
- [ ] Decide whether 3/5/7/9-second pause modes with three repeats and subtitles only on the last repeat are more valuable than cue-based sentence training.
- [ ] Decide whether slow-normal-fast progressive training should be a second phase of repeat-after-me training.

## Related Docs

- [Project structure](../knowledge-graph/0001_project-structure.md)
- [Transcript scroll state](../knowledge-graph/0004_transcript-scroll-state.md)
- [Video tap play/pause latency spec](../specs/0001_video-tap-play-pause-latency/spec.md)
- [Continue Watching, history, and sidebar progress spec](../specs/0002_continue-watching-history-progress/spec.md)
- [Transcript current cue through gaps spec](../specs/0003_transcript-current-cue-gaps/spec.md)
- [Minimal repeat-after-me training spec](../specs/0004_minimal-repeat-after-me-training/spec.md)
