import Foundation
import SwiftData
import Testing

@testable import ABPlayer

struct AnnotationServiceTests {

  @MainActor
  private struct TestContext {
    let container: ModelContainer
    let service: AnnotationService
  }

  @MainActor
  private func makeContext() throws -> TestContext {
    let schema = Schema([TextAnnotation.self])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    let service = AnnotationService(modelContext: container.mainContext)
    return TestContext(container: container, service: service)
  }

  @Test @MainActor
  func testAddAnnotation() throws {
    let context = try makeContext()
    let service = context.service
    let cueID = UUID()

    let display = service.addAnnotation(
      cueID: cueID,
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      type: .vocabulary
    )

    #expect(display.type == .vocabulary)
    #expect(display.selectedText == "hello")
    #expect(display.range.location == 0)
    #expect(display.range.length == 5)
    #expect(display.comment == nil)
  }

  @Test @MainActor
  func testAnnotationsForCue() throws {
    let context = try makeContext()
    let service = context.service
    let cueID = UUID()

    service.addAnnotation(cueID: cueID, range: NSRange(location: 0, length: 5), selectedText: "hello", type: .vocabulary)
    service.addAnnotation(cueID: cueID, range: NSRange(location: 6, length: 5), selectedText: "world", type: .collocation)

    let annotations = service.annotations(for: cueID)
    #expect(annotations.count == 2)
  }

  @Test @MainActor
  func testAnnotationsForDifferentCues() throws {
    let context = try makeContext()
    let service = context.service
    let cue1 = UUID()
    let cue2 = UUID()

    service.addAnnotation(cueID: cue1, range: NSRange(location: 0, length: 5), selectedText: "hello", type: .vocabulary)
    service.addAnnotation(cueID: cue2, range: NSRange(location: 0, length: 5), selectedText: "world", type: .collocation)

    #expect(service.annotations(for: cue1).count == 1)
    #expect(service.annotations(for: cue2).count == 1)
  }

  @Test @MainActor
  func testEmptyCueReturnsEmptyArray() throws {
    let context = try makeContext()
    let service = context.service
    let result = service.annotations(for: UUID())
    #expect(result.isEmpty)
  }

  @Test @MainActor
  func testUpdateComment() throws {
    let context = try makeContext()
    let service = context.service
    let cueID = UUID()

    let display = service.addAnnotation(
      cueID: cueID,
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      type: .vocabulary
    )

    service.updateComment(annotationID: display.id, comment: "This is a note")

    let annotations = service.annotations(for: cueID)
    #expect(annotations.first?.comment == "This is a note")
  }

  @Test @MainActor
  func testUpdateCommentByGroupAffectsAllSegments() throws {
    let context = try makeContext()
    let service = context.service
    let cue1 = UUID()
    let cue2 = UUID()
    let groupID = UUID()

    _ = service.addAnnotation(
      cueID: cue1,
      groupID: groupID,
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      type: .vocabulary
    )
    _ = service.addAnnotation(
      cueID: cue2,
      groupID: groupID,
      range: NSRange(location: 0, length: 5),
      selectedText: "world",
      type: .vocabulary
    )

    service.updateComment(groupID: groupID, comment: "shared note")

    let grouped = service.annotations(inGroup: groupID)
    #expect(grouped.count == 2)
    #expect(grouped.allSatisfy { $0.comment == "shared note" })
  }

  @Test @MainActor
  func testUpdateType() throws {
    let context = try makeContext()
    let service = context.service
    let cueID = UUID()

    let display = service.addAnnotation(
      cueID: cueID,
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      type: .vocabulary
    )

    service.updateType(annotationID: display.id, type: .goodSentence)

    let annotations = service.annotations(for: cueID)
    #expect(annotations.first?.type == .goodSentence)
  }

  @Test @MainActor
  func testUpdateTypeByGroupAffectsAllSegments() throws {
    let context = try makeContext()
    let service = context.service
    let cue1 = UUID()
    let cue2 = UUID()
    let groupID = UUID()

    _ = service.addAnnotation(
      cueID: cue1,
      groupID: groupID,
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      type: .vocabulary
    )
    _ = service.addAnnotation(
      cueID: cue2,
      groupID: groupID,
      range: NSRange(location: 0, length: 5),
      selectedText: "world",
      type: .vocabulary
    )

    service.updateType(groupID: groupID, type: .goodSentence)

    let grouped = service.annotations(inGroup: groupID)
    #expect(grouped.count == 2)
    #expect(grouped.allSatisfy { $0.type == .goodSentence })
  }

  @Test @MainActor
  func testRemoveAnnotation() throws {
    let context = try makeContext()
    let service = context.service
    let cueID = UUID()

    let display = service.addAnnotation(
      cueID: cueID,
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      type: .vocabulary
    )

    service.removeAnnotation(id: display.id)

    #expect(service.annotations(for: cueID).isEmpty)
  }

  @Test @MainActor
  func testRemoveAnnotationGroupRemovesAllSegments() throws {
    let context = try makeContext()
    let service = context.service
    let cue1 = UUID()
    let cue2 = UUID()
    let groupID = UUID()

    _ = service.addAnnotation(
      cueID: cue1,
      groupID: groupID,
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      type: .vocabulary
    )
    _ = service.addAnnotation(
      cueID: cue2,
      groupID: groupID,
      range: NSRange(location: 0, length: 5),
      selectedText: "world",
      type: .collocation
    )

    service.removeAnnotationGroup(groupID: groupID)

    #expect(service.annotations(for: cue1).isEmpty)
    #expect(service.annotations(for: cue2).isEmpty)
    #expect(service.annotations(inGroup: groupID).isEmpty)
  }

  @Test @MainActor
  func testVersionIncrementsOnAdd() throws {
    let context = try makeContext()
    let service = context.service
    let initialVersion = service.version

    service.addAnnotation(
      cueID: UUID(),
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      type: .vocabulary
    )

    #expect(service.version > initialVersion)
  }

  @Test @MainActor
  func testVersionIncrementsOnUpdate() throws {
    let context = try makeContext()
    let service = context.service
    let cueID = UUID()

    let display = service.addAnnotation(
      cueID: cueID,
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      type: .vocabulary
    )

    let versionAfterAdd = service.version
    service.updateComment(annotationID: display.id, comment: "note")
    #expect(service.version > versionAfterAdd)
  }

  @Test @MainActor
  func testVersionIncrementsOnRemove() throws {
    let context = try makeContext()
    let service = context.service
    let cueID = UUID()

    let display = service.addAnnotation(
      cueID: cueID,
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      type: .vocabulary
    )

    let versionAfterAdd = service.version
    service.removeAnnotation(id: display.id)
    #expect(service.version > versionAfterAdd)
  }

  @Test @MainActor
  func testRemoveNonExistentAnnotation() throws {
    let context = try makeContext()
    let service = context.service
    let versionBefore = service.version
    service.removeAnnotation(id: UUID())
    #expect(service.version == versionBefore)
  }
}
