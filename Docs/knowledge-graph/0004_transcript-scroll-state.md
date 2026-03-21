# Transcript Scroll State Design

## Summary

When the user manually scrolls the transcript, auto-scroll pauses and stays paused until the user explicitly resumes it — either by tapping the Resume button or by tapping a cue. Tapping a cue also seeks playback to that position.

## Details

### How It Works

- **User scrolls** → auto-scroll pauses, a Resume button appears.
- **User taps a cue** → playback seeks to that cue, auto-scroll resumes.
- **User taps Resume button** → auto-scroll resumes without seeking.
- **Track changes** → state resets, auto-scroll resumes.

Scroll state does **not** reset automatically when the scroll gesture ends. This is intentional.

### Where the State Is Consumed

| Site | Effect |
|---|---|
| `TranscriptTextView.updateNSView` | Suppresses auto-scroll to active cue while paused |
| `SubtitleViewModel.updateCurrentCue` | Freezes active-cue tracking while paused |
| `SubtitleView` Resume button | Shown while paused, hidden while auto-scrolling |

### Note on `isUserScrolling` and `mouseDown`

`mouseDown` does not check `isUserScrolling` because cue taps depend on `mouseDown` setting up internal state (`isDragging`, `dragAnchorIndex`) that `mouseUp` reads to fire `onCueTap`. Blocking `mouseDown` would silently swallow cue taps, preventing seek and scroll-state reset.

## Related Docs

- [Project Structure](./0001_project-structure.md)
