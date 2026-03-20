# Resolved Tech Debt (2026-03-20 Review)

## Summary

This archive captures debt items resolved from the 2026-03-20 codebase review. The active debt tracker keeps only current debt and links here for historical context.

---

## Details

| Item | Resolved In | Notes |
|------|-------------|-------|
| TD-001 `MainSplitViewModel` pane-allocation sprawl | unreleased (2026-03-20) | Extracted `MainSplitPaneAllocationState`; `MainSplitViewModel` now delegates pane allocation/persistence logic |
| TD-002 scattered `UserDefaults` key literals | unreleased (2026-03-20) | Added centralized `UserDefaultsKey` and migrated key usage |
| TD-003 mixed comment language | unreleased (2026-03-20) | Translated touched model/service comments to English (`AudioModels`, `Folder`, `FolderImporter`, `PlaybackRecord`, `TextAnnotation`, `Vocabulary`) |
| TD-004 `SubtitleViewModel.perform(action:)` growth risk | unreleased (2026-03-20) | Removed `Action` enum dispatch; switched callers to direct method API |
| TD-005 plugin system internal-surface ambiguity | unreleased (2026-03-20) | Documented `Plugin` protocol as internal-only first-party API |
| TD-006 `TranscriptionManager` lacks protocol boundary | unreleased (2026-03-20) | Added `TranscriptionEngineProtocol` + `WhisperKitTranscriptionEngine`; `TranscriptionManager` now depends on protocol |
| `FolderNavigationViewModel` monolithic navigation/selection/deletion/import logic | extracted via service delegation | `NavigationService`, `SelectionStateService`, `DeletionService`, `ImportService` |
| Thin wrapper APIs (`refreshCurrentFolderAndQueue`, `clearAllDataAsync`) | `0e7f046` | Inlined at call sites |
| Unused font token `Font.xs` | `0e7f046` | Removed from Typography |
| Force-unwraps in critical paths | `6ed3dac` | Replaced with guard / optional chaining |
| Redundant `SubtitleViewModel.Input` wrapper | `0e7f046` | Flattened to direct `Action` enum |
| HuggingFace network call on every load | `538db62` | `localModelFolder()` bypasses network if model exists |

---

## Related Docs

- [Code quality observations and active debt](../0002_code-quality-and-tech-debt.md)
- [Project structure and architecture overview](../0001_project-structure.md)
