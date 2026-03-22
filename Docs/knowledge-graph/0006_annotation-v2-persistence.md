# Annotation V2 Persistence

## Summary

Annotations now persist across app relaunches for newly created data. ABPlayer writes new annotations to V2 tables and uses stable subtitle cue IDs, so the same subtitle line keeps the same identity after reload. Legacy annotation rows are not migrated and are no longer used by runtime reads.

## Details

### User-visible behavior

- New annotations created after this change should still appear after reopening the app.
- Existing legacy annotations (created before V2) are intentionally not restored.
- Editing subtitle text does not change cue identity as long as cue timing/order stays the same.

### Data model (V2)

- `TextAnnotationGroupV2`
  - `audioFileID`, `stylePresetID`, `selectedTextSnapshot`, `comment`, timestamps.
- `TextAnnotationSpanV2`
  - `audioFileID`, `cueID`, `cueStartTime`, `cueEndTime`, local range, `segmentOrder`, timestamps.

Runtime annotation reads/writes are handled by `AnnotationService` using only V2 models.

### Stable cue identity

- `SubtitleCue.id` is now deterministic instead of random when cues are parsed or transcribed.
- Cue ID key: `audioFileID + cueIndex + startTime(ms) + endTime(ms)`.
- This keeps annotation-to-cue links stable after app restart and subtitle reload.

### Key implementation points

- V2 models added to schema in `ABPlayerApp`.
- `SubtitleLoader` passes `audioFileID` into subtitle parsing.
- `TranscriptionManager` generates deterministic cue IDs during transcription.
- Selection segments carry cue timing so V2 spans can store `cueStartTime` and `cueEndTime`.

## Related Docs

- [Annotation Style System Redesign](./0005_annotation-style-system-redesign.md)
- [ABPlayer Architecture Overview](./0001_project-structure.md)
