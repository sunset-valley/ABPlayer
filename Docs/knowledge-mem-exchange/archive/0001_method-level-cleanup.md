# Method-Level Cleanup Pass

## Summary

Method-level cleanup completed for the currently reachable declaration graph in `ABPlayer/Sources`.
Latest pass continues light refactor cleanup after dead-code convergence, then re-verified build/tests.

## Next Actions

1. Continue light refactor cleanup (non-functional changes): remove thin single-call wrappers in view models only when readability improves.
2. Keep dead-code cleanup in maintenance mode: re-run zero-reference scan after feature merges or large refactors.
3. Preserve these intentionally retained single-call APIs unless architecture changes:
   - `PlayerManager.addPlaybackTimeObserver(_:)` (used by `SubtitleViewModel.trackPlayback`)
   - `SubtitleParser.detectFormat(from:)` + `SubtitleFormat` (parser internal dispatch)
4. No current test-only helper surfaces remain from the previous retention list; they were removed in the latest cleanup batch.
5. For future removals/refactors, verify no dynamic/selector/runtime usage before deleting.
6. After each future cleanup/refactor batch, run:
   - `xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayer -destination 'platform=macOS' build 2>&1 | tail -20`
   - `tuist test`
7. Keep this section as an in-place checkpoint (do not append history).

## Latest Completed Batch

- Refactor cleanup in `ABPlayer/Sources/ViewModels/MainSplitViewModel.swift`:
  - Removed thin wrapper `handleSelectedFileMediaTypeChange(_:)`
  - Removed thin wrapper `syncSelectedFileWithPlayer()`
  - Removed thin wrapper `handleImportResult(_:)`
  - Removed thin wrapper `setImporterPresented(_:)`
- Updated call sites in `ABPlayer/Sources/Views/MainSplitView.swift`:
  - Inlined media-type switching guard + branch in `.onChange(of: selectedFile?.isVideo)`
  - Directly called `folderNavigationViewModel?.syncSelectedFileWithPlayer()` in `.onChange(of: playerManager.currentFile?.id)`
  - Inlined importer presentation binding set logic (clear `presetnImportType` when dismissed)
  - Routed importer completion directly to `folderNavigationViewModel?.handleImportResult(_:)`

## Test Updates In This Batch

- No test code changes were required in this batch; existing coverage remained valid after wrapper removal and call-site inlining.

## Verification Snapshot

- Build command passed:
  - `xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayer -destination 'platform=macOS' build 2>&1 | tail -20`
- Test command passed:
  - `tuist test`
- Current status:
  - Dead-code cleanup: converged (no additional high-confidence zero-reference declarations found in `ABPlayer/Sources`).
  - Refactor cleanup: in progress (small wrapper inlining and API-surface tightening).
  - Remaining one-hit API is intentional: `PlayerManager.addPlaybackTimeObserver(_:)` is used by subtitle playback tracking.

## Related Docs

- [Project structure](../knowledge-graph/0001_project-structure.md)
- [Agent entry and rules](../../AGENTS.md)
- [Project target/source-of-truth](../../Project.swift)
