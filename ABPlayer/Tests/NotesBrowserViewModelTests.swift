import Foundation
import SwiftData
import Testing

@testable import ABPlayerDev

struct NotesBrowserViewModelTests {

  @MainActor
  private struct TestContext {
    let container: ModelContainer
    let styleService: AnnotationStyleService
    let annotationService: AnnotationService
    let service: NotesBrowserService
  }

  @MainActor
  private func makeContext() throws -> TestContext {
    let schema = Schema([
      AnnotationStylePreset.self,
      ABFile.self,
      TextAnnotationGroupV2.self,
      TextAnnotationSpanV2.self,
      NoteCollection.self,
      Note.self,
      NoteEntry.self,
      NoteAnnotationLink.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    let styleService = AnnotationStyleService(modelContext: container.mainContext)
    let annotationService = AnnotationService(
      modelContext: container.mainContext,
      styleService: styleService
    )
    let service = NotesBrowserService(modelContext: container.mainContext)
    return TestContext(
      container: container,
      styleService: styleService,
      annotationService: annotationService,
      service: service
    )
  }

  @MainActor
  private func makeMediaFile(name: String, type: FileType) -> ABFile {
    ABFile(
      displayName: name,
      fileType: type,
      bookmarkData: Data([0x00]),
      createdAt: Date()
    )
  }

  @MainActor
  @discardableResult
  private func insertAnnotationGroup(
    container: ModelContainer,
    mediaID: UUID,
    stylePresetID: UUID = UUID(),
    text: String,
    comment: String?
  ) throws -> TextAnnotationGroupV2 {
    let now = Date()
    let group = TextAnnotationGroupV2(
      audioFileID: mediaID,
      stylePresetID: stylePresetID,
      selectedTextSnapshot: text,
      comment: comment,
      createdAt: now,
      updatedAt: now
    )
    container.mainContext.insert(group)
    try container.mainContext.save()
    return group
  }

  @MainActor
  private func createAnnotationGroup(
    context: TestContext,
    mediaID: UUID,
    cueID: UUID = UUID(),
    stylePresetID: UUID? = nil,
    selectedText: String,
    comment: String?
  ) -> UUID {
    let resolvedStylePresetID = stylePresetID ?? context.styleService.defaultStyle().id
    let selection = CrossCueTextSelection(
      segments: [
        .init(
          cueID: cueID,
          cueStartTime: 0,
          cueEndTime: 1,
          localRange: NSRange(location: 0, length: max(1, selectedText.count)),
          text: selectedText
        ),
      ],
      fullText: selectedText,
      globalRange: NSRange(location: 0, length: max(1, selectedText.count))
    )

    let created = context.annotationService.addAnnotation(
      audioFileID: mediaID,
      selection: selection,
      stylePresetID: resolvedStylePresetID
    )

    guard let groupID = created.first?.groupID else {
      Issue.record("Expected group ID")
      return UUID()
    }

    if let comment {
      context.annotationService.updateComment(groupID: groupID, comment: comment)
    }

    return groupID
  }

  @Test @MainActor
  func testOnAppearDefaultsToAllVideosAndMediaMode() throws {
    let context = try makeContext()
    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)

    let output = viewModel.transform(input: .init(event: .onAppear))

    #expect(output.selectedSource == .media(.allVideos))
    #expect(output.middleMode == .media)
  }

  @Test @MainActor
  func testSelectCollectionSwitchesToNotesModeAndListsNotes() throws {
    let context = try makeContext()
    let collection = try context.service.createCollection(name: "Study")
    let note = try context.service.createNote(collectionID: collection.id, title: "Lesson 1")

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))

    let output = viewModel.transform(input: .init(event: .selectSource(.collection(collection.id))))

    #expect(output.middleMode == .notes)
    #expect(output.middleItems.count == 1)
    #expect(output.middleItems.first?.title == "Lesson 1")
    #expect(output.selectedMiddleItem == .note(note.id))
    #expect(output.exportSelection?.kind == .note(noteID: note.id, noteTitle: "Lesson 1"))
  }

  @Test @MainActor
  func testMediaSelectionShowsAnnotationEntries() throws {
    let context = try makeContext()
    let media = makeMediaFile(name: "video.mp4", type: .video)
    context.container.mainContext.insert(media)
    let group = try insertAnnotationGroup(
      container: context.container,
      mediaID: media.id,
      text: "snapshot",
      comment: "memo"
    )

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))

    let output = viewModel.transform(input: .init(event: .selectMiddleItem(.media(media.id))))

    #expect(output.entries.count == 1)
    #expect(output.entries.first?.kind == .annotation)
    #expect(output.entries.first?.title == "snapshot")
    #expect(output.entries.first?.note == "memo")
    #expect(output.entries.first?.annotationGroupID == group.id)
    #expect(output.exportSelection?.kind == .media(mediaID: media.id, mediaName: media.displayName))
  }

  @Test @MainActor
  func testExportSelectionClearsWhenSourceSwitchesBackToMedia() throws {
    let context = try makeContext()
    let collection = try context.service.createCollection(name: "Study")
    let note = try context.service.createNote(collectionID: collection.id, title: "Lesson 1")

    let media = makeMediaFile(name: "video.mp4", type: .video)
    context.container.mainContext.insert(media)
    _ = try insertAnnotationGroup(
      container: context.container,
      mediaID: media.id,
      text: "snapshot",
      comment: "memo"
    )

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))
    let collectionOutput = viewModel.transform(input: .init(event: .selectSource(.collection(collection.id))))

    #expect(collectionOutput.selectedMiddleItem == .note(note.id))
    #expect(collectionOutput.exportSelection?.kind == .note(noteID: note.id, noteTitle: "Lesson 1"))

    let mediaOutput = viewModel.transform(input: .init(event: .selectSource(.media(.allVideos))))

    #expect(mediaOutput.middleMode == .media)
    #expect(mediaOutput.selectedMiddleItem == .media(media.id))
    #expect(mediaOutput.exportSelection?.kind == .media(mediaID: media.id, mediaName: media.displayName))
  }

  @Test @MainActor
  func testEntryFilterOptionsAndFilteringByStylePreset() throws {
    let context = try makeContext()
    let media = makeMediaFile(name: "video.mp4", type: .video)
    context.container.mainContext.insert(media)

    let styleA = AnnotationStylePreset(
      name: "Style A",
      kind: .underline,
      underlineColorHex: "#ff0000",
      backgroundColorHex: "#00000000",
      sortOrder: 0
    )
    let styleB = AnnotationStylePreset(
      name: "Style B",
      kind: .background,
      underlineColorHex: "#00ff00",
      backgroundColorHex: "#0000ff",
      sortOrder: 1
    )
    context.container.mainContext.insert(styleA)
    context.container.mainContext.insert(styleB)

    _ = try insertAnnotationGroup(
      container: context.container,
      mediaID: media.id,
      stylePresetID: styleA.id,
      text: "A",
      comment: "a"
    )
    _ = try insertAnnotationGroup(
      container: context.container,
      mediaID: media.id,
      stylePresetID: styleB.id,
      text: "B",
      comment: "b"
    )

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))

    let output = viewModel.transform(input: .init(event: .selectMiddleItem(.media(media.id))))

    #expect(output.entryFilterOptions.count == 3)
    #expect(output.entryFilterOptions.contains(where: { $0.filter == .all }))
    #expect(output.entryFilterOptions.contains(where: { $0.filter == .stylePreset(styleA.id) }))
    #expect(output.entryFilterOptions.contains(where: { $0.filter == .stylePreset(styleB.id) }))
    #expect(output.entries.count == 2)

    let filtered = viewModel.transform(input: .init(event: .selectEntryFilter(.stylePreset(styleA.id))))

    #expect(filtered.selectedEntryFilter == .stylePreset(styleA.id))
    #expect(filtered.entries.count == 1)
    #expect(filtered.entries.first?.stylePresetID == styleA.id)
    #expect(filtered.exportFilter == .stylePreset(styleA.id))
  }

  @Test @MainActor
  func testCreateCollectionCreatesAndSelectsIt() throws {
    let context = try makeContext()
    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))

    let output = viewModel.transform(input: .init(event: .createCollection(name: "Study")))

    let collectionItems = output.leftSections.first(where: { $0.id == "collections" })?.items ?? []
    #expect(collectionItems.count == 1)
    #expect(collectionItems.first?.title == "Study")

    if case .collection(let id) = output.selectedSource {
      #expect(output.middleMode == .notes)
      _ = id
    } else {
      Issue.record("Expected collection source to be selected")
    }
    #expect(output.actionError == nil)
  }

  @Test @MainActor
  func testCreateCollectionWithDuplicateNameSurfacesError() throws {
    let context = try makeContext()
    _ = try context.service.createCollection(name: "Study")

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))

    let output = viewModel.transform(input: .init(event: .createCollection(name: "Study")))

    #expect(output.actionError != nil)
  }

  @Test @MainActor
  func testCreateNoteCreatesAndSelectsIt() throws {
    let context = try makeContext()
    let collection = try context.service.createCollection(name: "Study")

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))
    _ = viewModel.transform(input: .init(event: .selectSource(.collection(collection.id))))

    let output = viewModel.transform(input: .init(event: .createNote(collectionID: collection.id, title: "Lesson 1")))

    #expect(output.middleItems.count == 1)
    #expect(output.middleItems.first?.title == "Lesson 1")
    #expect(output.selectedMiddleItem == output.middleItems.first?.selection)
    #expect(output.actionError == nil)
  }

  @Test @MainActor
  func testCreateNoteWithEmptyTitleSurfacesError() throws {
    let context = try makeContext()
    let collection = try context.service.createCollection(name: "Study")

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))
    _ = viewModel.transform(input: .init(event: .selectSource(.collection(collection.id))))

    let output = viewModel.transform(input: .init(event: .createNote(collectionID: collection.id, title: "  ")))

    #expect(output.actionError != nil)
    #expect(output.middleItems.isEmpty)
  }

  @Test @MainActor
  func testAddEntryToNoteLinksAnnotationAndRefreshes() throws {
    let context = try makeContext()
    let collection = try context.service.createCollection(name: "Study")
    let note = try context.service.createNote(collectionID: collection.id, title: "Lesson 1")

    let media = makeMediaFile(name: "video.mp4", type: .video)
    context.container.mainContext.insert(media)
    let group = try insertAnnotationGroup(
      container: context.container,
      mediaID: media.id,
      text: "snapshot",
      comment: nil
    )

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))
    _ = viewModel.transform(input: .init(event: .selectMiddleItem(.media(media.id))))

    let addOutput = viewModel.transform(input: .init(event: .addEntryToNote(
      annotationGroupID: group.id,
      noteID: note.id
    )))
    #expect(addOutput.actionError == nil)

    _ = viewModel.transform(input: .init(event: .selectSource(.collection(collection.id))))
    let noteOutput = viewModel.transform(input: .init(event: .selectMiddleItem(.note(note.id))))
    #expect(noteOutput.entries.count == 1)
    #expect(noteOutput.entries.first?.annotationGroupID == group.id)
  }

  @Test @MainActor
  func testAddEntryToNoteWithDuplicateSurfacesError() throws {
    let context = try makeContext()
    let collection = try context.service.createCollection(name: "Study")
    let note = try context.service.createNote(collectionID: collection.id, title: "Lesson 1")

    let media = makeMediaFile(name: "video.mp4", type: .video)
    context.container.mainContext.insert(media)
    let group = try insertAnnotationGroup(
      container: context.container,
      mediaID: media.id,
      text: "snapshot",
      comment: nil
    )

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))
    _ = viewModel.transform(input: .init(event: .selectMiddleItem(.media(media.id))))
    _ = viewModel.transform(input: .init(event: .addEntryToNote(annotationGroupID: group.id, noteID: note.id)))

    let output = viewModel.transform(input: .init(event: .addEntryToNote(
      annotationGroupID: group.id,
      noteID: note.id
    )))
    #expect(output.actionError != nil)
  }

  @Test @MainActor
  func testRemoveAnnotationFromNoteOnlyUnlinksCurrentNote() throws {
    let context = try makeContext()
    let collection = try context.service.createCollection(name: "Study")
    let note = try context.service.createNote(collectionID: collection.id, title: "Lesson 1")

    let media = makeMediaFile(name: "video.mp4", type: .video)
    context.container.mainContext.insert(media)
    let groupID = createAnnotationGroup(
      context: context,
      mediaID: media.id,
      selectedText: "snapshot",
      comment: "memo"
    )
    _ = try context.service.addAnnotationToNote(noteID: note.id, annotationGroupID: groupID)

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service, annotationService: context.annotationService)
    _ = viewModel.transform(input: .init(event: .onAppear))

    let output = viewModel.transform(input: .init(event: .removeAnnotationFromNote(
      annotationGroupID: groupID,
      noteID: note.id
    )))

    #expect(output.actionError == nil)
    #expect((try context.service.entries(forNoteID: note.id)).isEmpty)
    #expect(context.service.entries(forMediaID: media.id).count == 1)
  }

  @Test @MainActor
  func testDeleteAnnotationRemovesItFromMediaAndAllLinkedNotes() throws {
    let context = try makeContext()
    let collection = try context.service.createCollection(name: "Study")
    let note = try context.service.createNote(collectionID: collection.id, title: "Lesson 1")

    let media = makeMediaFile(name: "video.mp4", type: .video)
    context.container.mainContext.insert(media)
    let groupID = createAnnotationGroup(
      context: context,
      mediaID: media.id,
      selectedText: "snapshot",
      comment: "memo"
    )
    _ = try context.service.addAnnotationToNote(noteID: note.id, annotationGroupID: groupID)

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service, annotationService: context.annotationService)
    _ = viewModel.transform(input: .init(event: .onAppear))

    let output = viewModel.transform(input: .init(event: .deleteAnnotation(annotationGroupID: groupID)))

    #expect(output.actionError == nil)
    #expect(context.service.entries(forMediaID: media.id).isEmpty)
    #expect((try context.service.entries(forNoteID: note.id)).isEmpty)
  }

  @Test @MainActor
  func testCollectionsForPickerIsPopulated() throws {
    let context = try makeContext()
    let c1 = try context.service.createCollection(name: "Alpha")
    let c2 = try context.service.createCollection(name: "Beta")
    _ = try context.service.createNote(collectionID: c1.id, title: "Note A")
    _ = try context.service.createNote(collectionID: c2.id, title: "Note B1")
    _ = try context.service.createNote(collectionID: c2.id, title: "Note B2")

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    let output = viewModel.transform(input: .init(event: .onAppear))

    #expect(output.collectionsForPicker.count == 2)
    let betaCollection = output.collectionsForPicker.first { $0.name == "Beta" }
    #expect(betaCollection?.notes.count == 2)
  }

  @Test @MainActor
  func testActionErrorClearsOnNextEvent() throws {
    let context = try makeContext()
    _ = try context.service.createCollection(name: "Study")

    let viewModel = NotesBrowserViewModel()
    viewModel.configureIfNeeded(notesService: context.service)
    _ = viewModel.transform(input: .init(event: .onAppear))

    let errorOutput = viewModel.transform(input: .init(event: .createCollection(name: "Study")))
    #expect(errorOutput.actionError != nil)

    let refreshOutput = viewModel.transform(input: .init(event: .refresh))
    #expect(refreshOutput.actionError == nil)
  }
}
