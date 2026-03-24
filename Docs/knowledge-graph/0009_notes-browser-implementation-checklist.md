# Notes Browser Implementation Checklist

## Summary

This checklist defines the V1 implementation order for the Notes Browser. It follows the agreed model (`Collection -> Note -> Entry`, plus annotation references), keeps `TextAnnotationGroupV2` as source of truth for media-native annotations, and minimizes migration risk by shipping in vertical slices.

## Details

### Phase 1: Data Model

- Add SwiftData models:
  - `Collection`
  - `Note`
  - `NoteEntry` (custom entry)
  - `NoteAnnotationLink` (annotation reference)
- Keep existing models unchanged:
  - `TextAnnotationGroupV2`
  - `TextAnnotationSpanV2`
- Add schema registration in app container.
- Define delete rules:
  - `Collection` delete cascades note-domain rows.
  - `TextAnnotationGroupV2` delete removes related links.
- Add service-level dedup constraints:
  - collection name uniqueness (case-insensitive)
  - note title uniqueness within collection
  - unique (`noteID`, `annotationGroupID`) link

### Phase 2: Service Layer

- Introduce `NotesBrowserService` (or equivalent) for note-domain operations.
- Required APIs:
  - collection CRUD
  - note CRUD
  - custom entry CRUD/reorder
  - add/remove annotation reference in note
  - list media with annotations (videos/audios)
  - list notes by collection
  - build right-column entries for selected media/note
- Keep annotation edits routed to `AnnotationService.updateComment(...)`.

### Phase 3: ViewModel Contract

- Add `NotesBrowserViewModel` using repo MVVM contract (`Input`, `Output`, `transform(input:)`).
- Inputs:
  - `onAppear`
  - `selectSource`
  - `selectMiddleItem`
  - `createCollection`, `renameCollection`, `deleteCollection`
  - `createNote`, `renameNote`, `deleteNote`
  - `createEntry`, `editEntry`, `deleteEntry`, `moveEntry`
  - `addAnnotationToNote`, `removeAnnotationFromNote`
  - `openEditSheet`, `saveEditSheet`
- Output state:
  - left source tree
  - middle list mode (`media` or `notes`)
  - right merged entries
  - sheet presentation/edit payload

### Phase 4: Window and UI Shell

- Add dedicated `WindowGroup(id: "notes-browser")`.
- Inject existing dependencies and new notes service.
- Build 3-column shell:
  - left: `Media` + `Collections`
  - middle: media list or notes list based on source
  - right: full entries list (no extra expand layer)
- Add context-aware empty states for each column.

### Phase 5: Editing UX

- Right column is read-first; editing opens sheet.
- Sheet modes:
  - custom entry editor (`title`, `note`)
  - annotation note editor (`comment`)
- Save behavior:
  - custom entry -> `NoteEntry`
  - annotation note -> `TextAnnotationGroupV2.comment`

### Phase 6: Cross-Linking Actions

- In media context, support `Add Annotation to Note`.
- In note context, support `Remove Annotation from Note`.
- Ensure link actions do not mutate annotation ownership (`ABFile` remains owner).

### Phase 7: Tests

- Model/service tests:
  - dedup constraints
  - delete cascades and link cleanup
  - same annotation linked to multiple notes
  - note with mixed entries (custom + annotation)
- ViewModel tests:
  - source switching (`Media` vs `Collections`)
  - middle mode switching (`media` vs `notes`)
  - right-column mapping correctness
  - sheet edit routing correctness
- UI tests (smoke):
  - create collection/note
  - add custom entry
  - link annotation into note
  - edit annotation comment from note and verify reflected in media context

### Phase 8: Rollout Order

- Slice A: data model + service + tests (no UI exposure).
- Slice B: window shell + read-only lists.
- Slice C: sheet editing + annotation-note linking.
- Slice D: polish (ordering, empty states, keyboard shortcuts).

## Related Docs

- [Notes Browser Window](./0007_annotation-browser-window.md)
- [Notes Browser Data Model](./0008_notes-browser-data-model.md)
- [Annotation V2 Persistence](./0006_annotation-v2-persistence.md)
