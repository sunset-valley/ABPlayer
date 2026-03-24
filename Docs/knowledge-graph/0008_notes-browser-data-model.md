# Notes Browser Data Model

## Summary

This document defines the minimal data model for the Notes Browser V1. It keeps media-native annotations as the source of truth, adds note-specific entities for organization, and uses reference links so one annotation can appear in multiple notes without duplication.

## Details

### Scope

- Keep existing annotation models unchanged:
  - `TextAnnotationGroupV2`
  - `TextAnnotationSpanV2`
- Add note-domain models:
  - `Collection`
  - `Note`
  - `NoteEntry` (custom entry only)
  - `NoteAnnotationLink` (reference to `TextAnnotationGroupV2`)

### Model Definitions

#### `Collection`

- `id: UUID`
- `name: String` (required)
- `createdAt: Date`
- `updatedAt: Date`

#### `Note`

- `id: UUID`
- `collectionID: UUID`
- `title: String` (required)
- `createdAt: Date`
- `updatedAt: Date`

#### `NoteEntry` (custom)

- `id: UUID`
- `noteID: UUID`
- `title: String` (required)
- `note: String?`
- `sortOrder: Int`
- `createdAt: Date`
- `updatedAt: Date`

#### `NoteAnnotationLink`

- `id: UUID`
- `noteID: UUID`
- `annotationGroupID: UUID` (`TextAnnotationGroupV2.id`)
- `sortOrder: Int`
- `createdAt: Date`

### Ownership and References

- `ABFile` owns `TextAnnotationGroupV2` (unchanged).
- `Collection` owns `Note`.
- `Note` owns custom `NoteEntry` rows.
- `Note` references annotations through `NoteAnnotationLink`.
- One annotation can be linked to many notes.
- One note can include annotations from multiple media.

### Display Mapping

- Right-column display rows are a union of:
  - custom entry (`NoteEntry.title + NoteEntry.note`)
  - annotation entry (`TextAnnotationGroupV2.selectedTextSnapshot + TextAnnotationGroupV2.comment`)
- For annotation entries:
  - display `title = selectedTextSnapshot`
  - display `note = comment`

### Edit Semantics

- Editing custom entries updates `NoteEntry`.
- Editing annotation entry note updates `TextAnnotationGroupV2.comment` directly.
- `NoteAnnotationLink` never stores annotation text/comment snapshots.

### Integrity Rules (Service-Level)

- Deduplicate collection names case-insensitively per user scope.
- Deduplicate note titles within the same collection.
- Deduplicate links by (`noteID`, `annotationGroupID`).
- Keep `sortOrder` dense and stable after insert/delete within a note.
- Validate foreign keys before write (note exists, annotation exists).

### Delete Rules

- Delete `Collection` -> cascade delete its `Note`, `NoteEntry`, and `NoteAnnotationLink`.
- Delete `Note` -> delete its `NoteEntry` and `NoteAnnotationLink` only.
- Delete `TextAnnotationGroupV2` -> remove related `NoteAnnotationLink` rows.

### Query Contracts (V1)

- Left `All Videos` / `All Audios`: media with at least one `TextAnnotationGroupV2`.
- Middle for media source: list filtered media.
- Middle for collection source: list notes in collection.
- Right for selected media: media-owned annotation entries.
- Right for selected note: merged entries (`NoteEntry` + linked annotations), sorted by `sortOrder` then `createdAt`.

## Related Docs

- [Notes Browser Window](./0007_annotation-browser-window.md)
- [Annotation V2 Persistence](./0006_annotation-v2-persistence.md)
- [ABPlayer Architecture Overview](./0001_project-structure.md)
