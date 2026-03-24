# UI Test Entry Regression (Notes Export)

## Summary

During the Notes Browser CSV export test work, we introduced a regression risk by changing app scene/window behavior while trying to stabilize UI tests. This briefly moved the solution direction away from product behavior safety (main app entry must remain the player). We reverted the risky scene change and moved the fix strategy to test-only entry control.

## Details

### User-visible risk

- The app launch experience could drift from the expected player-first entry.
- Test-driven scene changes risked shipping behavior that was only needed for test stability.

### What happened

1. We diagnosed a flaky UI test where the Notes Browser window sometimes appeared first.
2. While iterating quickly, we changed app scene declarations to force test behavior.
3. This touched real launch/window behavior and violated the product expectation that normal entry is the player.
4. The issue was caught immediately in review and reverted.

### Root cause

- We mixed two concerns in one place:
  - Product scene behavior (app entry, window lifecycle)
  - UI-test bootstrapping behavior
- The helper pattern using generic `File -> New Window` is not deterministic for feature-specific UI tests and can open the wrong scene.

### Corrective actions taken

- Restored product scene behavior so normal entry remains player-first.
- Kept feature routing under dedicated UI-test launch flags (feature-specific demo entry).
- Updated Notes export UI test to avoid generic `New Window` fallback and rely on dedicated test entry markers.

### Prevention actions

- For UI tests, use feature-specific launch arguments/environment and feature-specific loaded markers.
- Do not modify product scene defaults to satisfy test startup order.
- If window recovery is required, use a feature-specific open path instead of generic `New Window`.

## Related Docs

- [Notes Browser Window Spec](../knowledge-graph/0007_annotation-browser-window.md)
- [Transcript Scroll Regression (Bounce Back)](../postmortem/0001_transcript-scroll-regression.md)
