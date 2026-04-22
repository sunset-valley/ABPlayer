# Task Plan: Video Tap Play/Pause Latency

## Implementation Plan

1. Locate the existing video-area click and double-click handling path.
2. Identify how the Play/Pause HUD is currently triggered and how playback toggling is dispatched.
3. Add immediate HUD feedback for the first video-area click.
4. Add a short pending single-click play/pause delay.
5. Cancel the pending single-click action when a double-click is detected, then preserve fullscreen toggling.
6. Tune the delay only if manual verification shows that 180 ms is unreliable.
7. Add focused coverage around delayed single-click and double-click cancellation if the relevant layer is testable.

## Verification Plan

- Manually verify single-click HUD timing and delayed playback toggle.
- Manually verify double-click fullscreen does not toggle playback.
- Manually verify the first click in a double-click still shows HUD feedback.
- Run focused tests for the changed gesture or ViewModel scope if coverage is added.

## Risks / Open Questions

- The existing gesture stack may make click counting or cancellation timing platform-dependent.
- UI automation may not reliably cover double-click timing, so manual verification may be required.
- The final delay may need minor tuning after testing on real hardware.

## Progress Log

- 2026-04-22: Created plan from playback study roadmap P0.
