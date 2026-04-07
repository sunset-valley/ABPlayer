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
`DeterministicID.generate(from: relativePath)` produces SHA256-based UUIDs. Re-importing the same file always yields the same `ABFile` identity — essential for stable managed-library path mapping and transcription cache hits.

**Library-scoped permission model**
Media access is now rooted at `LibrarySettings` (single permission boundary). Active flows resolve media/subtitle/PDF via `library root + relativePath` and sibling path derivation (`.srt`, `.pdf`).

- `ABFile`, `Folder`, and `SubtitleFile` bookmark fields are retained as **legacy compatibility fields**.
- New code should not read or write per-file/per-folder bookmark data for managed-library media operations.

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

### Resolved Debt

Resolved debt history was moved to archive:

- [Resolved tech debt (2026-03-20 review)](./archive/0001_resolved-tech-debt-2026-03-20.md)

---

### Testing Gaps

| Area | Status | Notes |
|------|--------|-------|
| `PlayerManager` playback state | Covered via protocol mock | `PlayerEngineProtocol` enables isolation |
| `TranscriptionManager` orchestration | Partial — state machine only | No mock for WhisperKit calls (TD-006) |
| `MainSplitViewModel` layout transitions | Not covered | Requires view integration test |
| `FolderNavigationViewModel` sub-services | Not covered | `NavigationService`, `SelectionStateService`, `DeletionService`, `ImportService` each testable in isolation now — no tests yet |
| Library-scoped permission lifecycle | Partial | Session begin/end and relative-path resolution are covered by regression suites; full app relaunch scenario still needs integration coverage |

---

## Related Docs

- [Project structure and architecture overview](./0001_project-structure.md)
- [Agent entry and rules](../../CLAUDE.md)
- [Swift style rules](../../.agent/rules/swift-style.md)
- [MVVM boundaries](../../.agent/rules/mvvm.md)
