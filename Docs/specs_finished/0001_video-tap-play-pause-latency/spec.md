# Task Spec: Video Tap Play/Pause Latency

## Summary

Video-area single clicks should feel responsive without losing double-click fullscreen. The user should see immediate Play/Pause HUD feedback on the first click, while the actual play/pause action waits briefly so a second click can convert the gesture into fullscreen.

## Scope

- Video-area mouse/tap interaction for single-click play/pause and double-click fullscreen.
- Immediate Play/Pause HUD feedback on the first click.
- Delayed playback state change for single clicks.
- Cancellation of the pending single-click action when the user double-clicks.
- Focused unit coverage for the delayed single-click coordination logic.
- Focused UI coverage for the video-area click behavior using a stable UI-testing demo surface.

## Non-Goals

- Changing keyboard shortcuts, menu commands, or non-video playback controls.
- Redesigning the Play/Pause HUD visual style.
- Changing fullscreen behavior outside the existing double-click video-area interaction.
- Adding new gesture customization settings.

## Requirements

- A single click in the video area shows Play/Pause HUD feedback immediately.
- A single click toggles playback after a 180 ms delay.
- A double-click in the video area cancels the pending play/pause action and toggles fullscreen.
- The first click of a double-click sequence still produces immediate HUD feedback.
- If 180 ms proves unreliable during verification, the delay may be retuned to 200-220 ms.
- Add deterministic unit tests for the shared delayed single-click coordination logic, including cancellation.
- Add focused macOS UI tests that verify single-click feedback, eventual playback toggle, and double-click fullscreen behavior without an unwanted playback toggle.

## Constraints

- Double-click fullscreen must remain available.
- The behavior should avoid accidental playback toggles during normal double-click use.
- The solution should preserve existing playback state semantics outside the video-area click path.
- Do not prescribe internal gesture structure in this spec; implementation details belong in `plan.md`.
- UI tests should use stable, test-specific identifiers and deterministic demo state rather than depending on production media or fragile timing assumptions.

## Acceptance Criteria

- Single-clicking the video area shows HUD feedback without perceptible delay.
- Single-clicking toggles play/pause only after the configured short delay.
- Double-clicking toggles fullscreen and does not also toggle playback.
- The behavior feels responsive in manual testing.
- Focused unit tests cover delayed execution, cancellation, and replacement of pending single-click work.
- Focused UI tests cover the video-area single-click and double-click flows on a deterministic demo surface.

## Related Docs

- [Playback Study Roadmap](../../knowledge-mem-exchange/0004_playback-study-roadmap.md)
- [Documentation rules](../../../.agent/rules/doc.md)
- [Workflow rules](../../../.agent/rules/workflow.md)
