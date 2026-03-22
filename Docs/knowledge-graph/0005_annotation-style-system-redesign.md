# Annotation Style System Redesign

## Summary

ABPlayer will replace the legacy annotation category system with a new shared style-preset architecture. The old fixed `AnnotationType` model and type-based color configuration are being retired in favor of globally shared `AnnotationStylePreset` records. Each annotation will reference one preset, and any preset change will immediately update every annotation that uses it. Legacy annotation data is intentionally not preserved because the project is still in an early development phase and the old model is not considered useful enough to migrate.

## Details

### Decision Summary

The new annotation system follows these product and engineering decisions:

- Remove the fixed `AnnotationType` model entirely from the main annotation flow.
- Replace per-type hardcoded colors with global shared style presets.
- Let each annotation reference exactly one preset.
- Make preset updates live: editing a preset updates all annotations that reference it.
- Do not migrate legacy annotation data.
- Mark legacy annotation types as deprecated before removing them fully.
- Prevent deleting a preset if any annotation still references it; require the user to switch those annotations manually first.

### Why This Redesign Exists

The legacy annotation model mixes semantic categories, rendering rules, and persistence concerns in a way that is hard to evolve.

Current problems in the legacy design:

- `AnnotationType` hardcodes three semantic categories.
- `AnnotationColorConfig` hardcodes color rules by type.
- Rendering logic is duplicated across multiple attributed-string builders.
- Cross-cue annotations are represented indirectly by repeated records with the same `groupID`.
- The popover UI cannot support user-defined styles, add/remove flows, or per-style color editing cleanly.

The redesign separates concerns:

- Style presets define how annotations look.
- Annotation groups define what the user annotated.
- Annotation spans define where each annotation applies.
- Rendering consumes resolved styles from a single shared source.

### Legacy Types To Deprecate

These legacy types should receive deprecation comments and `@available(*, deprecated, message: ...)` annotations before the full cutover:

- `AnnotationType`
- `TextAnnotation`
- `AnnotationColorConfig`
- `AnnotationDisplayData`
- Legacy `AnnotationType` display helpers in `AnnotationMenuView`

The deprecation message should explicitly point to the new shared style-preset system.

### New Data Model

#### `AnnotationStylePreset`

Represents a globally shared annotation appearance preset.

Suggested fields:

- `id: UUID`
- `name: String`
- `kind: AnnotationStyleKind`
- `underlineColorHex: String?`
- `backgroundColorHex: String?`
- `sortOrder: Int`
- `createdAt: Date`
- `updatedAt: Date`

#### `AnnotationStyleKind`

Defines the rendering mode for a preset.

Cases:

- `underline`
- `background`
- `underlineAndBackground`

This avoids scattered boolean combinations and makes rendering logic easier to read.

#### `TextAnnotationGroup`

Represents one logical annotation created by the user.

Suggested fields:

- `id: UUID`
- `stylePresetID: UUID`
- `selectedTextSnapshot: String`
- `comment: String?`
- `createdAt: Date`
- `updatedAt: Date`

This is the main annotation entity used by UI and services.

#### `TextAnnotationSpan`

Represents one segment of a group inside a specific subtitle cue.

Suggested fields:

- `id: UUID`
- `groupID: UUID`
- `cueID: UUID`
- `rangeLocation: Int`
- `rangeLength: Int`
- `segmentOrder: Int`

This makes cross-cue annotations explicit instead of implicit.

### Persistence Strategy

The redesign should use SwiftData for both annotation content and style presets.

Why SwiftData is preferred here:

- The project is already using SwiftData for domain persistence.
- Shared presets and annotation groups belong to the same domain model.
- Storing both in the same persistence layer avoids split ownership between SwiftData and `UserDefaults`.
- The reference from annotation group to preset is simpler when both live in the model layer.

Because legacy annotation data is intentionally discarded, the schema can be updated directly without compatibility layers. The existing persistent-store reset path should be used to avoid crashes on startup after the schema change.

### Service Layer Changes

#### `AnnotationService`

The service should be rewritten around the new model.

Responsibilities:

- Create one `TextAnnotationGroup` plus one or more `TextAnnotationSpan` values.
- Query annotations by cue by joining spans back to their owning group and preset.
- Update annotation comments.
- Switch an annotation group to another preset.
- Remove a group and all of its spans.

#### `AnnotationStyleService`

A new service should manage the shared style library.

Responsibilities:

- Create default presets on first launch.
- List presets in display order.
- Create new presets.
- Update preset name, kind, underline color, and background color.
- Report usage count for a preset.
- Block deletion if any annotation group still references the preset.

Deletion rule:

- If a preset is referenced by one or more annotations, deletion must fail.
- The UI should show a message telling the user to switch those annotations manually before deleting the preset.

### Display Model Changes

The existing `AnnotationDisplayData` is tied to the legacy type-based architecture and should be replaced.

The new display model should be based on:

- annotation group identity
- resolved preset
- selected text snapshot
- comment
- local or global range as needed by the rendering layer

The UI should not need to understand any legacy category semantics.

### Rendering Simplification

The current rendering rules are duplicated across multiple places, including attributed-string creation and reapplication during text-view state changes. The redesign should consolidate that logic.

#### New rendering helpers

##### `ResolvedAnnotationStyle`

A small value type that contains the final rendering result needed by AppKit text rendering.

Suggested fields:

- `kind`
- `underlineColor: NSColor?`
- `backgroundColor: NSColor?`

##### `AnnotationStyleResolver`

Takes a preset and produces `ResolvedAnnotationStyle`.

##### `AnnotationAttributeApplicator`

Applies resolved style attributes to `NSAttributedString` or `NSTextStorage`.

This helper should become the only place that knows how to apply:

- background color
- underline style
- underline color

This removes the current duplication across:

- `AnnotatedStringBuilder`
- `UnifiedStringBuilder`
- `TranscriptTextView`

### Popover UI Redesign

`newSelectionMenu` in `AnnotationMenuView` should be redesigned from a simple menu into a shared-style picker and editor.

#### Popover structure

Top actions:

- `Copy`
- `Look Up`

Style section:

- list all shared presets
- preview each preset visually
- select a preset to create a new annotation
- allow editing the preset inline

Each preset row should support:

- preset name
- live style preview
- kind switching: underline / background / underline + background
- underline color editing
- background color editing
- delete action

Bottom action:

- `Add Style`

#### Shared behavior

Because presets are global and shared:

- editing a preset changes all annotations using that preset
- there is no per-annotation style snapshot
- the preset list is the single source of truth

#### Delete behavior

If the user tries to delete a preset that is still referenced:

- do not delete it
- show a clear warning
- ask the user to switch affected annotations first

Suggested message:

`This style is still in use. Switch affected annotations to another style before deleting it.`

### Removal of Legacy Semantics

The new system intentionally removes the fixed legacy semantic categories such as:

- Vocabulary
- Collocation
- Good Sentence

The user-visible classification is now represented entirely by style presets. If users want semantic meaning, they can encode that in the preset name.

This keeps the model smaller and removes the need to maintain a separate semantic layer that no longer fits the desired product direction.

### Implementation Plan

#### Phase 1: Legacy Marking

- Add deprecation comments and `@available(*, deprecated, message: ...)` to old annotation-related types.
- Keep behavior unchanged in this phase.

#### Phase 2: New Model Introduction

- Add `AnnotationStylePreset`.
- Add `TextAnnotationGroup`.
- Add `TextAnnotationSpan`.
- Update the app schema to use the new models.
- Ensure the persistent store resets cleanly.

#### Phase 3: Service Rewrite

- Rewrite `AnnotationService`.
- Add `AnnotationStyleService`.
- Add default-preset bootstrap logic.

#### Phase 4: Rendering Refactor

- Add `ResolvedAnnotationStyle`.
- Add `AnnotationStyleResolver`.
- Add `AnnotationAttributeApplicator`.
- Replace duplicated style application logic in transcript rendering.

#### Phase 5: UI Rewrite

- Redesign `AnnotationMenuView`.
- Replace old `Mark as...` rows with shared style rows.
- Add inline preset editing affordances.
- Add referenced-preset deletion guard and warning UI.

#### Phase 6: Test Rewrite

Replace legacy tests with tests for the new architecture:

- preset creation and update
- preset deletion blocked when referenced
- annotation group and span creation
- annotation lookup by cue
- rendering behavior for each style kind
- live propagation when preset values change

### Risks and Guardrails

#### Risks

- Schema replacement can break startup if the old store is not reset correctly.
- Rendering changes can regress annotation highlighting if attributed-string application is not centralized.
- Inline popover editing can become visually crowded if controls are not grouped carefully.

#### Guardrails

- Use the existing persistent-store reset path during the schema cutover.
- Keep all rendering rules inside one applicator/helper.
- Keep preset deletion logic in the service layer, not only in the view.
- Ensure at least one preset always exists so annotation creation remains possible.

## Related Docs

- [Project structure and architecture overview](./0001_project-structure.md)
- [Code quality observations and technical debt](./0002_code-quality-and-tech-debt.md)
- [Transcript scroll state design](./0004_transcript-scroll-state.md)
- [Workspace rules](../../.agent/rules/workspace.md)
- [Swift style rules](../../.agent/rules/swift-style.md)
- [MVVM boundaries](../../.agent/rules/mvvm.md)
