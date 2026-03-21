# Method-Level Cleanup Pass

## Summary

Method-level cleanup continues for `ABPlayer/Sources` with non-functional refactors focused on reducing thin wrappers and improving call-site clarity. The latest batch simplified selection-restore flow in `MainSplitViewModel` by inlining a single-use synchronization helper.

## Details

### Latest Completed Batch

- `MainSplitViewModel` method-level cleanup:
    - Inlined selected-file and player-file reconciliation directly in `restoreLastSelectionIfNeeded()`.
    - Removed the one-use helper `syncSelectedFileWithCurrentPlayerFile(...)`.
    - Preserved behavior: when a current player file resolves in storage, both `selectedFile` and `playerManager.currentFile` synchronize and return early.
    - Kept fallback flow unchanged (`selectedFile` mismatch handling and `lastSelectedAudioFileID` restore path).

### Verification Snapshot

- Build command passed:
    - `xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayer -destination 'platform=macOS' build 2>&1 | tail -20`
- Test command passed:
    - `tuist test`
- Current status:
    - Dead-code cleanup: converged (no new high-confidence zero-reference declarations identified).
    - Refactor cleanup: in progress (wrapper reductions, duplication extraction, and call-site readability cleanup).
    - Intentional one-hit API retained: `PlayerManager.addPlaybackTimeObserver(_:)`.

## Next Actions

1. Continue light refactor cleanup in view models, but only remove wrappers when the resulting call sites remain readable.
2. Keep dead-code cleanup in maintenance mode and rerun zero-reference scans after feature merges or larger refactors.
3. Preserve intentionally retained single-call APIs unless architecture changes:
    - `PlayerManager.addPlaybackTimeObserver(_:)` (used by subtitle playback tracking)
    - `SubtitleParser.detectFormat(from:)` + `SubtitleFormat` (parser internal dispatch)
4. Verify no dynamic/selector/runtime usage before removing future declarations.
5. After each cleanup batch, run:
    - `xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayer -destination 'platform=macOS' build 2>&1 | tail -20`
    - `tuist test`
6. Keep this document as an in-place checkpoint (do not append history).

## Related Docs

- [Project structure](../knowledge-graph/0001_project-structure.md)
- [Agent entry and rules](../../AGENTS.md)
- [Project target/source-of-truth](../../Project.swift)
- [Method-level cleanup playbook](../mem-backbone/0001_method-level-cleanup-playbook.md)
