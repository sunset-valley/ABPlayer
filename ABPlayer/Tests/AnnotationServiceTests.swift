import Foundation
import SwiftData
import Testing

@testable import ABPlayerDev

struct AnnotationServiceTests {

  @MainActor
  private struct TestContext {
    let container: ModelContainer
    let styleService: AnnotationStyleService
    let service: AnnotationService
  }

  @MainActor
  private func makeContext() throws -> TestContext {
    let schema = Schema([
      AnnotationStylePreset.self,
      TextAnnotationGroup.self,
      TextAnnotationSpan.self,
    ])
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: config)
    let styleService = AnnotationStyleService(modelContext: container.mainContext)
    let service = AnnotationService(modelContext: container.mainContext, styleService: styleService)
    return TestContext(container: container, styleService: styleService, service: service)
  }

  @Test @MainActor
  func testAddAnnotationCreatesGroupAndSpans() throws {
    let context = try makeContext()
    let service = context.service
    let style = context.styleService.defaultStyle()
    let cue1 = UUID()
    let cue2 = UUID()

    let selection = CrossCueTextSelection(
      segments: [
        .init(cueID: cue1, localRange: NSRange(location: 0, length: 5), text: "hello"),
        .init(cueID: cue2, localRange: NSRange(location: 2, length: 5), text: "world"),
      ],
      fullText: "hello\nworld",
      globalRange: NSRange(location: 0, length: 11)
    )

    let created = service.addAnnotation(selection: selection, stylePresetID: style.id)

    #expect(created.count == 2)
    #expect(service.annotations(for: cue1).count == 1)
    #expect(service.annotations(for: cue2).count == 1)
  }

  @Test @MainActor
  func testUpdateCommentByGroup() throws {
    let context = try makeContext()
    let service = context.service
    let style = context.styleService.defaultStyle()
    let cueID = UUID()

    let selection = CrossCueTextSelection(
      segments: [.init(cueID: cueID, localRange: NSRange(location: 0, length: 5), text: "hello")],
      fullText: "hello",
      globalRange: NSRange(location: 0, length: 5)
    )

    let created = service.addAnnotation(selection: selection, stylePresetID: style.id)
    guard let groupID = created.first?.groupID else {
      Issue.record("Expected group")
      return
    }

    service.updateComment(groupID: groupID, comment: "note")

    let annotations = service.annotations(inGroup: groupID)
    #expect(annotations.count == 1)
    #expect(annotations.first?.comment == "note")
  }

  @Test @MainActor
  func testUpdateStyleByGroup() throws {
    let context = try makeContext()
    let service = context.service
    let styleA = context.styleService.defaultStyle()
    let styleB = context.styleService.addStyle(name: "Second", kind: .background)
    let cueID = UUID()

    let selection = CrossCueTextSelection(
      segments: [.init(cueID: cueID, localRange: NSRange(location: 0, length: 5), text: "hello")],
      fullText: "hello",
      globalRange: NSRange(location: 0, length: 5)
    )

    let created = service.addAnnotation(selection: selection, stylePresetID: styleA.id)
    guard let groupID = created.first?.groupID else {
      Issue.record("Expected group")
      return
    }

    service.updateStyle(groupID: groupID, stylePresetID: styleB.id)
    let updated = service.annotations(inGroup: groupID)
    #expect(updated.first?.stylePresetID == styleB.id)
  }

  @Test @MainActor
  func testStyleUsageCount() throws {
    let context = try makeContext()
    let service = context.service
    let style = context.styleService.defaultStyle()
    let cueID = UUID()

    let selection = CrossCueTextSelection(
      segments: [.init(cueID: cueID, localRange: NSRange(location: 0, length: 5), text: "hello")],
      fullText: "hello",
      globalRange: NSRange(location: 0, length: 5)
    )
    _ = service.addAnnotation(selection: selection, stylePresetID: style.id)

    #expect(service.styleUsageCount(stylePresetID: style.id) == 1)
  }

  @Test @MainActor
  func testRemoveAnnotationGroupRemovesAllSpans() throws {
    let context = try makeContext()
    let service = context.service
    let style = context.styleService.defaultStyle()
    let cue1 = UUID()
    let cue2 = UUID()

    let selection = CrossCueTextSelection(
      segments: [
        .init(cueID: cue1, localRange: NSRange(location: 0, length: 3), text: "one"),
        .init(cueID: cue2, localRange: NSRange(location: 0, length: 3), text: "two"),
      ],
      fullText: "one\ntwo",
      globalRange: NSRange(location: 0, length: 7)
    )
    let created = service.addAnnotation(selection: selection, stylePresetID: style.id)
    guard let groupID = created.first?.groupID else {
      Issue.record("Expected group")
      return
    }

    service.removeAnnotationGroup(groupID: groupID)
    #expect(service.annotations(for: cue1).isEmpty)
    #expect(service.annotations(for: cue2).isEmpty)
    #expect(service.annotations(inGroup: groupID).isEmpty)
  }
}
