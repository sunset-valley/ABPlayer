# Code Quality Observations and Technical Debt

## Summary

This document records durable code quality observations, known architectural strengths, and active technical debt identified during a full-codebase review on 2026-03-20 (v0.2.13-92). It is intended as a living reference — update entries when debt is resolved or new patterns emerge.

---

## Details

### Architectural Strengths

**Layered dependencies (enforced)**
Dependencies flow downward only: Views → ViewModels → Services → Models. No cross-layer shortcuts observed. `PlayerEngineProtocol` is the exemplary case: `PlayerManager` never imports AVFoundation directly.

**Actor isolation done correctly**
- `@MainActor` on all Services and ViewModels ensures UI state safety without explicit `DispatchQueue.main` calls.
- `SessionRecorder` uses `@ModelActor` to isolate background SwiftData writes, avoiding main-thread contention.
- `PlayerEngine` runs on a background `actor` so AVPlayer time callbacks never block the UI.

**Deterministic file IDs**
`DeterministicID.generate(from: relativePath)` produces SHA256-based UUIDs. Re-importing the same file always yields the same `ABFile` identity — essential for bookmark recovery and transcription cache hits.

**Security-scoped bookmarks**
All media file access goes through `bookmark → URL resolution → scoped access → defer stopAccessing`. No known paths that bypass sandbox constraints.

**Protocol boundary for testability**
`PlayerEngineProtocol` lets `PlayerManager` tests use a mock engine without AVFoundation. Pattern should be extended if other hard-to-test I/O surfaces arise (e.g., WhisperKit in `TranscriptionManager`).

**FolderNavigationViewModel service delegation**
`FolderNavigationViewModel` no longer owns folder-navigation logic directly. It delegates to four focused sub-services: `NavigationService` (folder stack), `SelectionStateService` (selection + UserDefaults persistence), `DeletionService` (file/folder delete), `ImportService` (import + refresh). Each service is independently understandable and can be tested without constructing the full ViewModel. This pattern should be applied to `MainSplitViewModel` as well (see TD-001).

**API surface discipline**
Commit `0e7f046` removed thin wrappers, single-use helpers, and declaration-only APIs. This trend should be maintained: prefer inlining trivial one-line wrappers over preserving surface area.

---

### Active Technical Debt

No currently tracked active debt from the 2026-03-20 review. Items TD-001 through TD-006 were resolved and moved to the resolved table below.

---

### Resolved Debt (for reference)

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

### Testing Gaps

| Area | Status | Notes |
|------|--------|-------|
| `PlayerManager` playback state | Covered via protocol mock | `PlayerEngineProtocol` enables isolation |
| `TranscriptionManager` orchestration | Partial — state machine only | No mock for WhisperKit calls (TD-006) |
| `MainSplitViewModel` layout transitions | Not covered | Requires view integration test |
| `FolderNavigationViewModel` sub-services | Not covered | `NavigationService`, `SelectionStateService`, `DeletionService`, `ImportService` each testable in isolation now — no tests yet |
| Security-scoped bookmark resolution | Not covered | Requires sandboxed environment |

---

## Related Docs

- [Project structure and architecture overview](./0001_project-structure.md)
- [Agent entry and rules](../../CLAUDE.md)
- [Swift style rules](../../.agent/rules/swift-style.md)
- [MVVM boundaries](../../.agent/rules/mvvm.md)
