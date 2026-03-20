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

#### TD-001 — `MainSplitViewModel` has sprawling responsibilities
**Location:** `ABPlayer/Sources/ViewModels/MainSplitViewModel.swift`
**Description:** One ViewModel now manages panel layout persistence, media type switching (audio ↔ video), `PaneContent` tab allocation across two panes (leftTabs/rightTabs/selections, dedup, overlap removal, per-media-type UserDefaults persistence), playback queue sync, session restore, and full data wipe.
**Risk:** Medium-high. The pane allocation system (`PaneContent`, `Panel`, `sanitizeAllocations`, `loadTabs`, `persistTabs`, etc.) has grown into a sizeable subsystem within the same class. Following the `FolderNavigationViewModel` delegation pattern would significantly reduce complexity.
**Suggested fix:** Extract `PaneAllocationState` (or a `PaneAllocationService`) to own the tab lists, selections, and persistence logic. Keep `MainSplitViewModel` focused on media coordination and session restore.

#### TD-002 — `UserDefaults` keys are scattered
**Location:** Multiple files — `MainSplitViewModel`, `BasePlayerViewModel`, `FolderNavigationViewModel`, settings services.
**Description:** Each type defines its own key string literals. No central namespace or enum guards against key collisions or typos.
**Risk:** Low-medium. Risk increases as more state is persisted.
**Suggested fix:** Introduce a `UserDefaultsKey` enum (or `extension UserDefaults`) as a single source of truth for all key strings.

#### TD-003 — Mixed comment language
**Location:** `AudioModels.swift`, `Folder.swift`, `FolderImporter.swift`, others.
**Description:** Some files contain Chinese-language inline comments alongside English comments. Not a functional issue, but reduces codebase uniformity.
**Risk:** Low.
**Suggested fix:** Translate comments to English on next touch of each file. Doc rule already mandates English for docs.

#### TD-004 — `SubtitleViewModel.perform(action:)` growth risk
**Location:** `ABPlayer/Sources/Views/Subtitle/SubtitleViewModel.swift`
**Description:** The `Action` enum now has exactly 8 cases (`setPlayerManager`, `handleUserScroll`, `cancelScrollResume`, `handleTextSelection`, `handleCueTap`, `reset`, `trackPlayback`, `stopTrackingPlayback`) — at the monitoring threshold. The flat `perform(action:)` dispatch is still readable but has reached the point where further additions should be scrutinised.
**Risk:** Medium. The threshold has been reached.
**Suggested fix:** Do not add new `Action` cases without first evaluating whether to split by concern (scroll, selection, playback tracking). Consider a direct-method API over enum dispatch if the caller set is small and well-defined.

#### TD-005 — Plugin system is prototype-level
**Location:** `ABPlayer/Sources/Plugins/`
**Description:** `Plugin` protocol exposes only `id`, `name`, `icon`, `open()`. The only concrete plugin is `CounterPlugin` (sample). No lifecycle hooks, sandboxing, or inter-plugin communication.
**Risk:** Low as long as plugins remain first-party. High if third-party plugin loading is ever introduced.
**Suggested fix:** Document the plugin API as "internal only" until requirements for third-party extension are defined. Avoid growing the protocol surface ad-hoc.

#### TD-006 — `TranscriptionManager` lacks a testable protocol boundary
**Location:** `ABPlayer/Sources/Services/TranscriptionManager.swift`
**Description:** Unlike `PlayerEngine`, WhisperKit is called directly in `TranscriptionManager` with no abstraction layer. This makes it impossible to unit-test transcription orchestration without a real model download.
**Risk:** Low now (transcription tests verify state machine, not WhisperKit). Medium if orchestration logic becomes more complex.
**Suggested fix:** Extract a `WhisperKitProtocol` (or `TranscriptionEngineProtocol`) wrapping the WhisperKit call. Mirror the `PlayerEngineProtocol` pattern.

---

### Resolved Debt (for reference)

| Item | Resolved In | Notes |
|------|-------------|-------|
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
| `FolderNavigationViewModel` import flow | Not covered | `ImportService` / `FolderImporter` untested |
| Security-scoped bookmark resolution | Not covered | Requires sandboxed environment |

---

## Related Docs

- [Project structure and architecture overview](./0001_project-structure.md)
- [Agent entry and rules](../../CLAUDE.md)
- [Swift style rules](../../.agent/rules/swift-style.md)
- [MVVM boundaries](../../.agent/rules/mvvm.md)
