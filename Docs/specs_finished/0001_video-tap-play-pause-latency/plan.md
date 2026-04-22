# Task Plan: Video Tap Play/Pause Latency

## Implementation Plan

1. Replace the duplicated local click-delay tasks with one shared `@MainActor` coordinator used by both video surfaces.
    - Current code keeps separate `pendingSingleTap` tasks in `VideoPlayerView` and `FullscreenVideoContent`, both sleeping for 300 ms before showing HUD feedback and toggling playback.
    - Introduce a small coordinator whose only responsibility is: run immediate first-click feedback, schedule one delayed single-click action, cancel pending work on double-click or teardown, and replace older pending work when a newer single-click arrives.
    - Start with a default single-click playback delay of 180 ms.
    - Use `Task.sleep(for:)` in production.
    - Allow an injectable sleep closure so unit tests can drive the delayed path deterministically.
2. Route the normal video-area gestures through the shared coordinator.
    - On the first single click, show the existing Play/Pause HUD immediately instead of after the delay.
    - Schedule the actual `viewModel.togglePlayPause()` after the configured delay.
    - On double-click, cancel the pending playback toggle and keep the existing fullscreen toggle behavior.
    - Cancel pending click work when the normal video surface disappears.
3. Route fullscreen video-area gestures through the same coordinator instance.
    - Pass the coordinator from `VideoPlayerView` into the fullscreen presenter/content instead of maintaining a second independent pending task there.
    - On the first single click, show the existing fullscreen play/pause symbol HUD immediately.
    - Schedule the existing fullscreen single-tap playback action after the configured delay.
    - On double-click, cancel the pending playback toggle and keep the existing fullscreen dismiss behavior.
    - Cancel pending click work when fullscreen is dismissed so no delayed playback action survives the transition.
4. Add focused unit tests for the coordinator instead of trying to unit-test SwiftUI gesture dispatch.
    - Create a dedicated test file for the coordinator rather than extending `BusinessLogicTests.swift`.
    - Cover immediate feedback on first click.
    - Cover that delayed playback does not run before the sleep completes.
    - Cover that delayed playback runs after the sleep completes.
    - Cover that double-click cancellation prevents the delayed playback action.
    - Cover that repeated single-clicks replace older pending work so only the latest action can fire.
    - Cover explicit invalidation/disappear cleanup if the coordinator exposes it.
5. Add a focused UI-testing demo surface for the video tap behavior and drive it from `ABPlayerApp` UI test flags.
    - Follow the existing repository pattern of a dedicated demo view plus launch flags instead of trying to automate the full production window state.
    - Use deterministic state and stable accessibility identifiers for the video tap surface, HUD, playback state, and fullscreen state.
    - Prefer a mock-backed or otherwise deterministic `PlayerManager` setup for the UI test demo so playback state transitions are observable without depending on real media assets.
6. Add focused macOS UI tests for the click behavior.
    - Verify that single-clicking the video surface produces HUD feedback immediately.
    - Verify that single-clicking eventually toggles the playback state after the short delay.
    - Verify that double-clicking toggles fullscreen and does not also toggle playback.
    - Verify that the first click in a double-click sequence still surfaces HUD feedback.
    - Use coordinate-based clicks on the video surface if needed; do not rely on brittle assumptions about native video subview accessibility.
7. Preserve existing behavior outside the video-area click path.
    - Do not change keyboard shortcuts, menu commands, playback controls, seek controls, or non-video playback actions.
    - Do not redesign the HUD visual style or change subtitle overlay behavior.
    - Do not add gesture customization settings.
8. Retune only if manual verification shows the default delay is unreliable.
    - Start with 180 ms.
    - If normal double-click use still causes accidental playback toggles, retune the coordinator default to 200-220 ms.

## Verification Plan

- Focused unit coverage for the shared coordinator:
    - First click runs immediate HUD feedback synchronously.
    - First click does not toggle playback before the injected delay completes.
    - First click toggles playback after the injected delay completes.
    - Double-click cancellation prevents the pending delayed playback action from running.
    - Repeated single-click cancels older pending work so only the latest delayed action can run.
    - Explicit invalidation/disappear cleanup cancels pending work.
- Focused UI coverage on the dedicated video tap demo:
    - Single-click on the video surface shows HUD feedback without perceptible delay.
    - Single-click eventually changes the exposed playback-state indicator.
    - Double-click changes the exposed fullscreen-state indicator and does not change the playback-state indicator.
    - The first click in a double-click sequence still causes the HUD indicator to appear.
- Manual verification for the normal video area:
    - Single-click shows HUD without perceptible delay.
    - Single-click toggles playback only after the short delay.
    - Double-click enters fullscreen and does not also toggle playback.
    - The first click in a double-click sequence still shows HUD feedback.
- Manual verification for fullscreen video:
    - Single-click shows the fullscreen HUD without perceptible delay.
    - Single-click toggles playback only after the short delay.
    - Double-click exits fullscreen and does not also toggle playback.
- Focused command verification for the future implementation:
    - Run the targeted coordinator unit tests.
    - Run the targeted UI tests for the dedicated video tap demo.
    - Run the project build command from `.agent/rules/build.md`.

## Risks / Open Questions

- SwiftUI click-count dispatch can be platform-sensitive on macOS, so manual verification must decide whether 180 ms is sufficient.
- If one coordinator instance is shared across normal and fullscreen surfaces, its lifecycle must be explicit so fullscreen dismissal or normal-surface teardown cannot leave delayed playback work alive.
- UI automation may not reliably validate exact click timing, so unit tests should own the precise delay/cancellation assertions and UI tests should verify only the observable interaction outcomes.
- Fullscreen double-click is assumed to keep the current behavior of dismissing fullscreen.
- The dedicated UI test demo may need a mock-backed player path or explicit state labels because the existing video subtitle demo uses normal `PlayerManager` setup and empty media placeholders, which is not ideal for deterministic playback assertions.
- The final delay may need minor tuning after testing on real hardware.

## Progress Log

- 2026-04-22: Created plan from playback study roadmap P0.
- 2026-04-22: Expanded the plan from `spec.md` as a documentation-only update; selected a shared coordinator approach for future implementation without changing code.
- 2026-04-22: Reviewed current `VideoPlayerView` and `VideoFullscreenPresenter` behavior against the plan; documented that both still use separate 300 ms delayed tasks and that HUD feedback is currently delayed rather than immediate.
- 2026-04-22: Added focused unit-test and UI-test work items to the plan, including a dedicated UI-testing demo surface for deterministic video tap interaction coverage.
- 2026-04-22: Implemented a shared `VideoTapPlaybackCoordinator`, routed normal and fullscreen video click handling through it, and preserved immediate HUD feedback for single-click and double-click fullscreen paths.
- 2026-04-22: Added focused coordinator unit tests and a dedicated video tap UI-testing demo with focused macOS UI tests; targeted unit tests, targeted UI tests, and the project build all passed.
