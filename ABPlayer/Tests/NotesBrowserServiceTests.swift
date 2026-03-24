import Foundation
import SwiftData
import Testing

@testable import ABPlayerDev

struct NotesBrowserServiceTests {

  @MainActor
  private struct TestContext {
    let container: ModelContainer
    let styleService: AnnotationStyleService
    let annotationService: AnnotationService
    let notesService: NotesBrowserService
  }

  @MainActor
  private func makeContext() throws -> TestContext {
    let schema = Schema([
      ABFile.self,
      LoopSegment.self,
      AnnotationStylePreset.self,
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
    let notesService = NotesBrowserService(modelContext: container.mainContext)
    return TestContext(
      container: container,
      styleService: styleService,
      annotationService: annotationService,
      notesService: notesService
    )
  }

  @MainActor
  private func makeMediaFile(name: String, type: FileType = .audio) -> ABFile {
    ABFile(
      displayName: name,
      fileType: type,
      bookmarkData: Data([0x00]),
      createdAt: Date()
    )
  }

  @MainActor
  private func createAnnotationGroup(
    context: TestContext,
    mediaID: UUID,
    cueID: UUID,
    selectedText: String,
    comment: String?
  ) -> UUID {
    let style = context.styleService.defaultStyle()
    let selection = CrossCueTextSelection(
      segments: [
        .init(
          cueID: cueID,
          cueStartTime: 0,
          cueEndTime: 1,
          localRange: NSRange(location: 0, length: max(1, selectedText.count)),
          text: selectedText
        )
      ],
      fullText: selectedText,
      globalRange: NSRange(location: 0, length: max(1, selectedText.count))
    )

    let created = context.annotationService.addAnnotation(
      audioFileID: mediaID,
      selection: selection,
      stylePresetID: style.id
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
  func testCreateCollectionRejectsDuplicateNameCaseInsensitive() throws {
    let context = try makeContext()

    _ = try context.notesService.createCollection(name: "Study")

    #expect(
      throws: NotesBrowserServiceError.duplicateCollectionName,
      performing: {
        _ = try context.notesService.createCollection(name: "study")
      }
    )
  }

  @Test @MainActor
  func testCreateNoteRejectsDuplicateTitleWithinSameCollection() throws {
    let context = try makeContext()
    let collection = try context.notesService.createCollection(name: "French")

    _ = try context.notesService.createNote(collectionID: collection.id, title: "Lesson 1")

    #expect(
      throws: NotesBrowserServiceError.duplicateNoteTitle,
      performing: {
        _ = try context.notesService.createNote(collectionID: collection.id, title: "lesson 1")
      }
    )
  }

  @Test @MainActor
  func testCreateNoteAllowsSameTitleInDifferentCollections() throws {
    let context = try makeContext()
    let c1 = try context.notesService.createCollection(name: "A")
    let c2 = try context.notesService.createCollection(name: "B")

    _ = try context.notesService.createNote(collectionID: c1.id, title: "Shared")
    let note = try context.notesService.createNote(collectionID: c2.id, title: "Shared")

    #expect(note.title == "Shared")
  }

  @Test @MainActor
  func testAddAnnotationToNoteRejectsDuplicateLink() throws {
    let context = try makeContext()
    let media = makeMediaFile(name: "track.mp3", type: .audio)
    context.container.mainContext.insert(media)

    let groupID = createAnnotationGroup(
      context: context,
      mediaID: media.id,
      cueID: UUID(),
      selectedText: "hello",
      comment: "note"
    )

    let collection = try context.notesService.createCollection(name: "Study")
    let note = try context.notesService.createNote(collectionID: collection.id, title: "Week 1")

    _ = try context.notesService.addAnnotationToNote(noteID: note.id, annotationGroupID: groupID)

    #expect(
      throws: NotesBrowserServiceError.duplicateAnnotationLink,
      performing: {
        _ = try context.notesService.addAnnotationToNote(noteID: note.id, annotationGroupID: groupID)
      }
    )
  }

  @Test @MainActor
  func testSameAnnotationCanBeLinkedToMultipleNotes() throws {
    let context = try makeContext()
    let media = makeMediaFile(name: "track.mp3", type: .audio)
    context.container.mainContext.insert(media)

    let groupID = createAnnotationGroup(
      context: context,
      mediaID: media.id,
      cueID: UUID(),
      selectedText: "hello",
      comment: "note"
    )

    let collection = try context.notesService.createCollection(name: "Study")
    let n1 = try context.notesService.createNote(collectionID: collection.id, title: "N1")
    let n2 = try context.notesService.createNote(collectionID: collection.id, title: "N2")

    _ = try context.notesService.addAnnotationToNote(noteID: n1.id, annotationGroupID: groupID)
    _ = try context.notesService.addAnnotationToNote(noteID: n2.id, annotationGroupID: groupID)

    let e1 = try context.notesService.entries(forNoteID: n1.id)
    let e2 = try context.notesService.entries(forNoteID: n2.id)
    #expect(e1.count == 1)
    #expect(e2.count == 1)
    #expect(e1.first?.annotationGroupID == groupID)
    #expect(e2.first?.annotationGroupID == groupID)
  }

  @Test @MainActor
  func testDeleteCollectionCascadesNotesEntriesAndLinks() throws {
    let context = try makeContext()
    let media = makeMediaFile(name: "track.mp3", type: .audio)
    context.container.mainContext.insert(media)

    let groupID = createAnnotationGroup(
      context: context,
      mediaID: media.id,
      cueID: UUID(),
      selectedText: "hello",
      comment: "note"
    )

    let collection = try context.notesService.createCollection(name: "Study")
    let note = try context.notesService.createNote(collectionID: collection.id, title: "Lesson")
    _ = try context.notesService.createCustomEntry(noteID: note.id, title: "Custom", note: "Body")
    _ = try context.notesService.addAnnotationToNote(noteID: note.id, annotationGroupID: groupID)

    try context.notesService.deleteCollection(id: collection.id)

    #expect(context.notesService.collections().isEmpty)

    let notes = (try? context.container.mainContext.fetch(FetchDescriptor<Note>())) ?? []
    let entries = (try? context.container.mainContext.fetch(FetchDescriptor<NoteEntry>())) ?? []
    let links = (try? context.container.mainContext.fetch(FetchDescriptor<NoteAnnotationLink>())) ?? []

    #expect(notes.isEmpty)
    #expect(entries.isEmpty)
    #expect(links.isEmpty)

    let groups = (try? context.container.mainContext.fetch(FetchDescriptor<TextAnnotationGroupV2>())) ?? []
    #expect(groups.count == 1)
    #expect(groups.first?.id == groupID)
  }

  @Test @MainActor
  func testDeleteAnnotationCleansUpLinks() throws {
    let context = try makeContext()
    let media = makeMediaFile(name: "track.mp3", type: .audio)
    context.container.mainContext.insert(media)

    let groupID = createAnnotationGroup(
      context: context,
      mediaID: media.id,
      cueID: UUID(),
      selectedText: "hello",
      comment: "note"
    )

    let collection = try context.notesService.createCollection(name: "Study")
    let note = try context.notesService.createNote(collectionID: collection.id, title: "Lesson")
    _ = try context.notesService.addAnnotationToNote(noteID: note.id, annotationGroupID: groupID)

    context.annotationService.removeAnnotationGroup(groupID: groupID)
    try context.container.mainContext.save()

    let links = (try? context.container.mainContext.fetch(FetchDescriptor<NoteAnnotationLink>())) ?? []
    #expect(links.isEmpty)
  }

  @Test @MainActor
  func testEntriesForNoteReturnsMixedSortedItems() throws {
    let context = try makeContext()
    let media = makeMediaFile(name: "video.mp4", type: .video)
    context.container.mainContext.insert(media)

    let groupID = createAnnotationGroup(
      context: context,
      mediaID: media.id,
      cueID: UUID(),
      selectedText: "snapshot",
      comment: "comment"
    )

    let collection = try context.notesService.createCollection(name: "Study")
    let note = try context.notesService.createNote(collectionID: collection.id, title: "Lesson")
    _ = try context.notesService.createCustomEntry(noteID: note.id, title: "custom", note: "body")
    _ = try context.notesService.addAnnotationToNote(noteID: note.id, annotationGroupID: groupID)

    let entries = try context.notesService.entries(forNoteID: note.id)

    #expect(entries.count == 2)
    #expect(entries[0].kind == .custom)
    #expect(entries[0].title == "custom")
    #expect(entries[1].kind == .annotation)
    #expect(entries[1].title == "snapshot")
    #expect(entries[1].note == "comment")
    #expect(entries[1].annotationGroupID == groupID)
    #expect(entries[1].mediaName == media.displayName)
  }

  @Test @MainActor
  func testMediaWithAnnotationsFiltersByType() throws {
    let context = try makeContext()

    let audio = makeMediaFile(name: "audio.mp3", type: .audio)
    let video = makeMediaFile(name: "video.mp4", type: .video)
    let plain = makeMediaFile(name: "plain.mp3", type: .audio)
    context.container.mainContext.insert(audio)
    context.container.mainContext.insert(video)
    context.container.mainContext.insert(plain)

    _ = createAnnotationGroup(
      context: context,
      mediaID: audio.id,
      cueID: UUID(),
      selectedText: "a",
      comment: nil
    )
    _ = createAnnotationGroup(
      context: context,
      mediaID: video.id,
      cueID: UUID(),
      selectedText: "b",
      comment: nil
    )

    let audios = context.notesService.mediaWithAnnotations(fileType: .audio)
    let videos = context.notesService.mediaWithAnnotations(fileType: .video)
    let all = context.notesService.mediaWithAnnotations(fileType: nil)

    #expect(audios.map(\.id) == [audio.id])
    #expect(videos.map(\.id) == [video.id])
    #expect(all.count == 2)
    #expect(!all.contains(where: { $0.id == plain.id }))
  }

  @Test @MainActor
  func testEditingAnnotationCommentReflectsInNoteEntries() throws {
    let context = try makeContext()
    let media = makeMediaFile(name: "video.mp4", type: .video)
    context.container.mainContext.insert(media)

    let groupID = createAnnotationGroup(
      context: context,
      mediaID: media.id,
      cueID: UUID(),
      selectedText: "snapshot",
      comment: "before"
    )

    let collection = try context.notesService.createCollection(name: "Study")
    let note = try context.notesService.createNote(collectionID: collection.id, title: "Lesson")
    _ = try context.notesService.addAnnotationToNote(noteID: note.id, annotationGroupID: groupID)

    context.annotationService.updateComment(groupID: groupID, comment: "after")
    let entries = try context.notesService.entries(forNoteID: note.id)

    #expect(entries.count == 1)
    #expect(entries.first?.note == "after")
  }

  @Test @MainActor
  func testCSVExportForNoteIncludesCustomAndAnnotationRows() throws {
    let context = try makeContext()
    let media = makeMediaFile(name: "video.mp4", type: .video)
    context.container.mainContext.insert(media)

    let groupID = createAnnotationGroup(
      context: context,
      mediaID: media.id,
      cueID: UUID(),
      selectedText: "Snapshot \"quoted\",line",
      comment: "Line 1\nLine 2"
    )

    let collection = try context.notesService.createCollection(name: "Study")
    let note = try context.notesService.createNote(collectionID: collection.id, title: "Lesson")
    _ = try context.notesService.createCustomEntry(
      noteID: note.id,
      title: "Custom,Title",
      note: "Custom \"Note\""
    )
    _ = try context.notesService.addAnnotationToNote(noteID: note.id, annotationGroupID: groupID)

    let csvString = try context.notesService.csvString(forNoteID: note.id)

    let expected =
      "title,note\n\"Custom,Title\",\"Custom \"\"Note\"\"\"\n\"Snapshot \"\"quoted\"\",line\",\"Line 1\nLine 2\""

    #expect(csvString == expected)

    let csvData = try context.notesService.csvData(forNoteID: note.id)
    let decoded = String(decoding: csvData, as: UTF8.self)
    #expect(decoded == csvString)
  }

  @Test @MainActor
  func testCSVExportThrowsForMissingNote() throws {
    let context = try makeContext()

    #expect(
      throws: NotesBrowserServiceError.noteNotFound,
      performing: {
        _ = try context.notesService.csvString(forNoteID: UUID())
      }
    )
  }

  @Test @MainActor
  func testCSVExportForMediaIncludesAnnotationRows() throws {
    let context = try makeContext()
    let media = makeMediaFile(name: "audio.mp3", type: .audio)
    context.container.mainContext.insert(media)

    _ = createAnnotationGroup(
      context: context,
      mediaID: media.id,
      cueID: UUID(),
      selectedText: "Snapshot \"quoted\"",
      comment: "Line 1\nLine 2"
    )

    let csvString = try context.notesService.csvString(forMediaID: media.id)
    let expected = "title,note\n\"Snapshot \"\"quoted\"\"\",\"Line 1\nLine 2\""
    #expect(csvString == expected)

    let csvData = try context.notesService.csvData(forMediaID: media.id)
    let decoded = String(decoding: csvData, as: UTF8.self)
    #expect(decoded == csvString)
  }

  @Test @MainActor
  func testCSVExportThrowsForMissingMedia() throws {
    let context = try makeContext()

    #expect(
      throws: NotesBrowserServiceError.mediaNotFound,
      performing: {
        _ = try context.notesService.csvString(forMediaID: UUID())
      }
    )
  }
}
