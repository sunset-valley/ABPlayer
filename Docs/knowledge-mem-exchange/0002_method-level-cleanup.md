# Method-Level Cleanup Pass

## Summary

Method-level cleanup completed for the currently reachable declaration graph in `ABPlayer/Sources`.
Latest pass removed declaration-only APIs with zero production references and re-verified build/tests.

## Next Actions

1. Keep this task in maintenance mode: re-run a zero-reference scan only after feature merges or large refactors.
2. Preserve these intentionally retained single-call APIs unless architecture changes:
   - `PlayerManager.addPlaybackTimeObserver(_:)` (used by `SubtitleViewModel.trackPlayback`)
   - `SubtitleParser.detectFormat(from:)` + `SubtitleFormat` (parser internal dispatch)
3. Preserve these test-only helper surfaces unless test strategy changes:
   - `TranscriptionManager.isModelLoaded`
   - `SubtitleViewModel.TextSelectionState.selectedRange`
   - `SubtitleViewModel.TextSelectionState.annotationCueID`
4. For future removals, verify no dynamic/selector/runtime usage before deleting.
5. After each future cleanup batch, run:
   - `xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayer -destination 'platform=macOS' build 2>&1 | tail -20`
   - `tuist test`
6. Keep this section as an in-place checkpoint (do not append history).

## Latest Completed Batch

- Removed `SubtitleViewModel.transform(input:)` and `SubtitleViewModel.transform(_:)` from `ABPlayer/Sources/Views/Subtitle/SubtitleViewModel.swift`.
- Removed `SubtitleViewModel.Input` wrapper and flattened action API to `SubtitleViewModel.Action` in `ABPlayer/Sources/Views/Subtitle/SubtitleViewModel.swift`.
- Removed unused action cases from `SubtitleViewModel.Action`:
  - `.updateCurrentCue`
  - `.dismissSelection`
- Removed `ImportError.invalidDirectory` from `ABPlayer/Sources/Services/FolderImporter.swift`.
- Removed view-model forwarders with zero callers from `ABPlayer/Sources/ViewModels/FolderNavigationViewModel.swift`:
  - `addAudioFile(from:)`
  - `importFolder(from:)`
- Removed unused plugin lookup API `plugin(withID:)` from `ABPlayer/Sources/Plugins/PluginManager.swift`.
- Removed unused overloads from `ABPlayer/Sources/Services/SubtitleLoader.swift`:
  - `loadSubtitles(from subtitleFile:)`
  - `loadSubtitles(from bookmarkData:)`
  - `loadSubtitles(from:withSecurityScope:)` (replaced by `loadSubtitles(from:)`)
- Removed unused helper `containsParagraphIndex(_:)` from `ABPlayer/Sources/Views/TextView/Models/CueLayout.swift`.
- Removed unused helper `annotation(at:in:)` from `ABPlayer/Sources/Services/AnnotationService.swift`.
- Removed unused computed property `isPlaybackComplete` from `ABPlayer/Sources/Models/AudioModels.swift`.
- Removed unused computed property `rootFolder` from `ABPlayer/Sources/Models/Folder.swift`.
- Removed unused convenience accessor `crossCueSelection` from `ABPlayer/Sources/Views/Subtitle/SubtitleViewModel.swift`.
- Removed unused async property `avPlayer` from `ABPlayer/Sources/Services/PlayerManager/PlayerManager.swift`.

## Test Updates In This Batch

- Removed `testContainsParagraphIndexFullRange` from `ABPlayer/Tests/CueLayoutTests.swift`.
- Removed `testAnnotationAtCharacterIndex` from `ABPlayer/Tests/AnnotationServiceTests.swift`.

## Verification Snapshot

- Build command passed:
  - `xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayer -destination 'platform=macOS' build 2>&1 | tail -20`
- Test command passed:
  - `tuist test`
- Current status: no additional high-confidence zero-reference declarations found in `ABPlayer/Sources` by automated + manual sweep.

## Related Docs

- [Project structure](../knowledge-graph/0001_project-structure.md)
- [Agent entry and rules](../../AGENTS.md)
- [Project target/source-of-truth](../../Project.swift)
