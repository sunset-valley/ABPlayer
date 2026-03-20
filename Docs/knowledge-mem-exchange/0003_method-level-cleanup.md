# Method-Level Cleanup Pass

## Summary

Method-level cleanup continues for `ABPlayer/Sources` with non-functional refactors focused on reducing thin wrappers and improving naming clarity at call sites.
This pass archived the previous checkpoint and established a new in-place handoff note.

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

## Latest Completed Batch

- Documentation cleanup and consolidation:
  - Archived stale session analysis doc to `Docs/knowledge-mem-exchange/archive/0003_project-analysis-2026-03-20.md`
  - Kept active handoff focused on current cleanup stream only
  - Added reusable playbook `Docs/mem-backbone/0001_method-level-cleanup-playbook.md`
  - Updated `Docs/mem-backbone/.config` to reflect new document ID consumption

## Test Updates In This Batch

- No code changes in this batch; build/test verification state remains from the latest completed cleanup pass.

## Verification Snapshot

- Build command passed:
  - `xcodebuild -workspace ABPlayer.xcworkspace -scheme ABPlayer -destination 'platform=macOS' build 2>&1 | tail -20`
- Test command passed:
  - `tuist test`
- Current status:
  - Dead-code cleanup: converged (no new high-confidence zero-reference declarations identified).
  - Refactor cleanup: in progress (small wrapper reductions, naming cleanup, and readability/dedup extractions).
  - Intentional one-hit API retained: `PlayerManager.addPlaybackTimeObserver(_:)`.

## Related Docs

- [Project structure](../knowledge-graph/0001_project-structure.md)
- [Agent entry and rules](../../AGENTS.md)
- [Project target/source-of-truth](../../Project.swift)
- [Method-level cleanup playbook](../mem-backbone/0001_method-level-cleanup-playbook.md)
