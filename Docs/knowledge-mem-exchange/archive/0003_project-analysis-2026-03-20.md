# Project Analysis Handoff — 2026-03-20

## Summary

Full codebase review conducted on 2026-03-20 at v0.2.13-92. This document records the current state, outstanding questions, and recommended next actions for the next session picking up this work.

---

## Details

### Current State

- **Version:** 0.2.13-92 (latest release commit `158015e`)
- **Last significant refactor:** `0e7f046` — removed unused declaration-only APIs, pruned API surface
- **Working tree:** 9 files modified (unstaged), including `SubtitleViewModel`, `AudioPlayerViewModel`, `FolderNavigationViewModel`, `MainSplitViewModel`, `TranscriptionManager`, `AudioPlayerView`, `MainSplitView`, `Typography`, and one test file.

### What Was Done This Session

- Performed a full architecture and code quality review across all 92 source files and 10 test suites.
- Identified 6 active technical debt items (TD-001 through TD-006) — documented in [knowledge-graph/0002_code-quality-and-tech-debt.md](../knowledge-graph/0002_code-quality-and-tech-debt.md).
- No code was modified this session; this was a read-only analysis.

### Unstaged Changes Summary

The 9 modified files in the working tree have not been committed. Their changes predate this session. Before the next feature or fix, confirm intent:

| File | Nature of change (not yet inspected) |
|------|---------------------------------------|
| `Typography.swift` | Likely token cleanup (per recent `0e7f046` pattern) |
| `TranscriptionManager.swift` | Possible state machine or settings change |
| `AudioPlayerViewModel.swift` | Unknown — inspect before next commit |
| `FolderNavigationViewModel.swift` | Unknown |
| `MainSplitViewModel.swift` | Possible layout/persistence change |
| `AudioPlayerView.swift` | UI adjustment |
| `MainSplitView.swift` | UI adjustment |
| `SubtitleViewModel.swift` | Unknown |
| `SubtitleViewModelTests.swift` | Test updates (possibly for removed APIs) |
| `TranscriptionTests.swift` | Test updates |

### Recommended Next Actions

1. **Review and commit unstaged changes** — Inspect each modified file; group into logical commits following the quick-commit convention in `workflow.md`.

2. **Address TD-001 (MainSplitViewModel)** — Extract `PanelLayoutState`. This is the highest-priority debt item by architecture impact.

3. **Address TD-002 (UserDefaults keys)** — Low effort, high long-term value. A `UserDefaultsKey` enum can be done in one PR.

4. **Fix comment language (TD-003)** — Can be done opportunistically on next touch of each file.

5. **Evaluate plugin system intent (TD-005)** — Decide: internal-only forever, or open to third parties? That decision gates how much to invest in the plugin protocol.

### Open Questions

- Are the 9 unstaged changes a single in-progress feature or independent cleanup items?
- Is there a roadmap for expanding the plugin system beyond `CounterPlugin`?
- Is `TranscriptionManager` planned to grow (more orchestration complexity)? If yes, TD-006 (WhisperKit protocol) becomes higher priority.

---

## Related Docs

- [Architecture overview](../../knowledge-graph/0001_project-structure.md)
- [Code quality and tech debt](../../knowledge-graph/0002_code-quality-and-tech-debt.md)
- [Workflow and commit conventions](../../../.agent/rules/workflow.md)
