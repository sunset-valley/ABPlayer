import AppKit
import Foundation
import Testing

@testable import ABPlayer

struct AnnotationStyleKindTests {

  @Test
  func testRawValues() {
    #expect(AnnotationStyleKind.underline.rawValue == "underline")
    #expect(AnnotationStyleKind.background.rawValue == "background")
    #expect(AnnotationStyleKind.underlineAndBackground.rawValue == "underlineAndBackground")
  }

  @Test
  func testCodableRoundTrip() throws {
    let original = AnnotationStyleKind.underlineAndBackground
    let data = try JSONEncoder().encode(original)
    let decoded = try JSONDecoder().decode(AnnotationStyleKind.self, from: data)
    #expect(decoded == original)
  }
}

struct NSColorHexTests {

  @Test
  func testHexRoundTrip() {
    let color = NSColor.systemBlue
    let hex = color.abHexString
    let parsed = NSColor(abHex: hex)
    #expect(parsed != nil)
  }

  @Test
  func testInvalidHexReturnsNil() {
    #expect(NSColor(abHex: "#XYZXYZ") == nil)
    #expect(NSColor(abHex: "#1234") == nil)
  }
}

struct AnnotationRenderDataTests {

  @Test
  func testResolvedStyleFromDisplayData() {
    let styleID = UUID()
    let data = AnnotationRenderData(
      id: UUID(),
      groupID: UUID(),
      stylePresetID: styleID,
      styleName: "Underline",
      styleKind: .underline,
      underlineColorHex: "#FF0000",
      backgroundColorHex: "#00FF00",
      range: NSRange(location: 0, length: 5),
      selectedText: "hello",
      comment: nil
    )

    #expect(data.styleDisplay.id == styleID)
    #expect(data.resolvedStyle.kind == .underline)
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
