# Transcript Scroll Regression (Bounce Back)

## Summary

In the v0.2.25 development cycle, the transcript panel could scroll but bounce back instead of staying at the intended position. We also observed `Modifying state during view update` warnings during the same workstream. The incident caused unreliable transcript navigation and increased UI test flakiness risk.

## Details

### User-visible impact

- Long transcript scrolling could rebound after user scroll.
- Width changes could produce inconsistent effective scroll range.
- UI test demo emitted SwiftUI state-update timing warnings.

### Root cause

1. We use a custom TextKit setup with `heightTracksTextView = false`. After attributed-string updates and width changes, the `documentView` height was not always recomputed from laid-out content.
2. Scroll metrics were published synchronously during `updateNSView`, which can trigger SwiftUI state mutation during view update.

### What fixed it

- Added explicit document-size synchronization using `layoutManager.usedRect(for:) + textContainerInset`.
- Recomputed document size on both full rebuild and width changes.
- Deferred scroll-metrics callback delivery to the next main-actor turn and coalesced updates.
- Added UI regression coverage:
    - scroll reaches near-bottom and does not bounce back;
    - width change recomputes scrollable metrics.

### Prevention rules (keep)

- If `NSTextContainer.heightTracksTextView == false`, always maintain `documentView` height explicitly after content/width changes.
- Do not call SwiftUI state-mutating callbacks synchronously from `updateNSView`; dispatch asynchronously on `@MainActor`.
- Any transcript scrolling/layout change must run:
    - `xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayerDev -destination 'platform=macOS' test -only-testing:ABPlayerUITests/TranscriptScrollUITests`

## Related Docs

- [Transcript Scroll State Design](../knowledge-graph/0004_transcript-scroll-state.md)
- [UI Testing Gate Playbook](../mem-backbone/0002_ui-testing-gate-playbook.md)
