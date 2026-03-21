import AppKit
import Foundation
import Testing

@testable import ABPlayer

struct AnnotationTypeTests {

  @Test
  func testRawValues() {
    #expect(AnnotationType.vocabulary.rawValue == "vocabulary")
    #expect(AnnotationType.collocation.rawValue == "collocation")
    #expect(AnnotationType.goodSentence.rawValue == "goodSentence")
  }

  @Test
  func testAllCases() {
    #expect(AnnotationType.allCases.count == 3)
    #expect(AnnotationType.allCases.contains(.vocabulary))
    #expect(AnnotationType.allCases.contains(.collocation))
    #expect(AnnotationType.allCases.contains(.goodSentence))
  }

  @Test
  func testCodableRoundTrip() throws {
    let original = AnnotationType.goodSentence
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AnnotationType.self, from: data)
    #expect(decoded == original)
  }

  @Test
  func testDisplayName() {
    #expect(AnnotationType.vocabulary.displayName == "Vocabulary")
    #expect(AnnotationType.collocation.displayName == "Collocation")
    #expect(AnnotationType.goodSentence.displayName == "Good Sentence")
  }
}

struct AnnotationColorConfigTests {

  @Test
  func testDefaultColors() {
    let config = AnnotationColorConfig.default
    #expect(config.vocabulary == .systemRed)
    #expect(config.collocation == .systemBlue)
    #expect(config.goodSentence == .systemYellow)
  }

  @Test
  func testColorForType() {
    let config = AnnotationColorConfig.default
    #expect(config.color(for: .vocabulary) == .systemRed)
    #expect(config.color(for: .collocation) == .systemBlue)
    #expect(config.color(for: .goodSentence) == .systemYellow)
  }

  @Test
  func testCustomColors() {
    let config = AnnotationColorConfig(
      vocabulary: .systemOrange,
      collocation: .systemGreen,
      goodSentence: .systemPurple
    )
    #expect(config.color(for: .vocabulary) == .systemOrange)
    #expect(config.color(for: .collocation) == .systemGreen)
    #expect(config.color(for: .goodSentence) == .systemPurple)
  }

  @Test
  func testEquality() {
    let a = AnnotationColorConfig.default
    let b = AnnotationColorConfig.default
    #expect(a == b)

    let c = AnnotationColorConfig(
      vocabulary: .systemOrange,
      collocation: .systemBlue,
      goodSentence: .systemYellow
    )
    #expect(a != c)
  }
}

struct AnnotationDisplayDataTests {

  @Test
  func testEquality() {
    let id = UUID()
    let groupID = UUID()
    let range = NSRange(location: 0, length: 5)
    let a = AnnotationDisplayData(id: id, groupID: groupID, type: .vocabulary, range: range, selectedText: "hello", comment: nil)
    let b = AnnotationDisplayData(id: id, groupID: groupID, type: .vocabulary, range: range, selectedText: "hello", comment: nil)
    #expect(a == b)
  }

  @Test
  func testInequalityDifferentType() {
    let id = UUID()
    let groupID = UUID()
    let range = NSRange(location: 0, length: 5)
    let a = AnnotationDisplayData(id: id, groupID: groupID, type: .vocabulary, range: range, selectedText: "hello", comment: nil)
    let b = AnnotationDisplayData(id: id, groupID: groupID, type: .collocation, range: range, selectedText: "hello", comment: nil)
    #expect(a != b)
  }

  @Test
  func testFromTextAnnotation() {
    let cueID = UUID()
    let annotation = TextAnnotation(
      cueID: cueID,
      rangeLocation: 5,
      rangeLength: 10,
      type: .goodSentence,
      selectedText: "test phrase",
      comment: "nice!"
    )

    let display = AnnotationDisplayData(from: annotation)
    #expect(display.id == annotation.id)
    #expect(display.groupID == annotation.groupID)
    #expect(display.type == .goodSentence)
    #expect(display.range.location == 5)
    #expect(display.range.length == 10)
    #expect(display.selectedText == "test phrase")
    #expect(display.comment == "nice!")
  }

  @Test
  func testTextAnnotationDefaultGroupIDMatchesID() {
    let annotation = TextAnnotation(
      cueID: UUID(),
      rangeLocation: 0,
      rangeLength: 4,
      type: .vocabulary,
      selectedText: "test"
    )

    #expect(annotation.groupID == annotation.id)
  }
}

struct TextSelectionRangeTests {

  @Test
  func testEquality() {
    let cueID = UUID()
    let a = TextSelectionRange(cueID: cueID, range: NSRange(location: 0, length: 5), selectedText: "hello")
    let b = TextSelectionRange(cueID: cueID, range: NSRange(location: 0, length: 5), selectedText: "hello")
    #expect(a == b)
  }

  @Test
  func testInequalityDifferentRange() {
    let cueID = UUID()
    let a = TextSelectionRange(cueID: cueID, range: NSRange(location: 0, length: 5), selectedText: "hello")
    let b = TextSelectionRange(cueID: cueID, range: NSRange(location: 1, length: 5), selectedText: "ello ")
    #expect(a != b)
  }
}
