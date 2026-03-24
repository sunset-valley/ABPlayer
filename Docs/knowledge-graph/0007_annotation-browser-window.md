# Notes Browser Window

## Summary

ABPlayer adds a dedicated Notes Browser window to manage study notes outside playback. The UI uses three columns with context switching: left selects sources (`Media` or `Collections`), middle shows either media or notes, and right shows full entries for the current selection. Editing always happens in a sheet.

## Details

### Terms

- `Collection`: user-defined container of notes.
- `Note`: a titled note that belongs to one collection.
- `Entry` (`Item`): a content row inside a note.
- `Annotation`: media-native annotation (`TextAnnotationGroupV2`) owned by media.
- `Media`: `ABFile` (audio/video).

### Information Architecture

- Left column sections:
  - `Media`
    - `All Videos`
    - `All Audios`
  - `Collections`
    - user-created collection list
- `All Videos` and `All Audios` show only media that currently has annotations.
- Middle column behavior:
  - If source is `All Videos`/`All Audios`: show matching media list.
  - If source is a `Collection`: show notes in that collection.
- Right column behavior:
  - If middle selection is media: show that media's annotation entries.
  - If middle selection is note: show that note's entries.
- Right column rows show full content directly (no extra expand level).
- Editing opens a sheet.

### Entry Semantics

- A note can contain mixed entry types:
  - Custom entry: `title + note`.
  - Annotation entry reference: `selectedTextSnapshot + comment`.
- For annotation entries:
  - `title` maps to `selectedTextSnapshot`.
  - `note` maps to `comment`.
- Editing an annotation entry's note updates the original `TextAnnotationGroupV2.comment` (single source of truth).

### Ownership and Relationships

- Media ownership remains unchanged:
  - `ABFile` contains many `TextAnnotationGroupV2`.
- Notes system:
  - `Collection` contains many `Note`.
  - `Note` has its own required `title`.
  - `Note` contains many custom entries.
  - `Note` can reference many annotations.
- A single annotation can be referenced by multiple notes.

### Interaction Rules

- Add annotation to note uses reference semantics, not copy semantics.
- Removing annotation from a note removes only the reference; annotation remains under its media.
- Deleting a note deletes only note-scoped data (title, custom entries, references), not underlying annotations.

### MVVM and Service Boundaries

- Keep subtitle rendering and annotation CRUD in `AnnotationService`.
- Add a browser/note service for `Collection`, `Note`, custom entries, and annotation-note links.
- Browser ViewModel owns source switching, middle list loading, right entry mapping, and sheet edit actions.

### Initial Scope

- Dedicated browser window (`WindowGroup`) separate from playback layout.
- Source switching across media and collections.
- Mixed entry rendering in right column.
- Sheet-based editing for both custom entries and annotation comments.

### Out of Scope (V1)

- Drag-and-drop assignment.
- Advanced global search beyond current column context.
- Embedding browser into the main playback split layout.

## Related Docs

- [Annotation V2 Persistence](./0006_annotation-v2-persistence.md)
- [Annotation Style System Redesign](./0005_annotation-style-system-redesign.md)
- [ABPlayer Architecture Overview](./0001_project-structure.md)
