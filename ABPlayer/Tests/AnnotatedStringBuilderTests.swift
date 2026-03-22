import AppKit
import Foundation
import Testing

@testable import ABPlayerDev

struct AnnotatedStringBuilderTests {

  @Test
  func testPlainTextNoAnnotations() {
    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: []
    )

    let result = builder.build(text: "Hello world test")
    #expect(result.attributedString.string == "Hello world test")
  }

  @Test
  func testEmptyText() {
    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: []
    )

    let result = builder.build(text: "")
    #expect(result.attributedString.string.isEmpty)
  }

  @Test
  func testFontApplied() {
    let fontSize: Double = 20.0
    let builder = AnnotatedStringBuilder(
      fontSize: fontSize,
      defaultTextColor: .labelColor,
      annotations: []
    )

    let result = builder.build(text: "Test")
    let attributes = result.attributedString.attributes(at: 0, effectiveRange: nil)

    if let font = attributes[.font] as? NSFont {
      #expect(abs(font.pointSize - fontSize) < 0.01)
    } else {
      Issue.record("Font attribute not found")
    }
  }

  @Test
  func testDefaultTextColor() {
    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: []
    )

    let result = builder.build(text: "Hello")
    let attributes = result.attributedString.attributes(at: 0, effectiveRange: nil)
    let color = attributes[.foregroundColor] as? NSColor
    #expect(color == .labelColor)
  }

  private func makeAnnotation(
    kind: AnnotationStyleKind,
    range: NSRange,
    selectedText: String,
    underlineHex: String = "#FF0000",
    backgroundHex: String = "#00AAFF"
  ) -> AnnotationRenderData {
    AnnotationRenderData(
      id: UUID(),
      groupID: UUID(),
      stylePresetID: UUID(),
      styleName: "Style",
      styleKind: kind,
      underlineColorHex: underlineHex,
      backgroundColorHex: backgroundHex,
      range: range,
      selectedText: selectedText,
      comment: nil
    )
  }

  @Test
  func testUnderlineStyleApplied() {
    let annotation = makeAnnotation(kind: .underline, range: NSRange(location: 0, length: 5), selectedText: "Hello")

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [annotation]
    )

    let result = builder.build(text: "Hello world")
    let attributes = result.attributedString.attributes(at: 2, effectiveRange: nil)

    let underline = attributes[.underlineStyle] as? Int
    #expect(underline == NSUnderlineStyle.single.rawValue)

    // Non-annotated text should remain default
    let normalAttributes = result.attributedString.attributes(at: 6, effectiveRange: nil)
    let normalColor = normalAttributes[.foregroundColor] as? NSColor
    #expect(normalColor == .labelColor)
  }

  @Test
  func testBackgroundStyleApplied() {
    let annotation = makeAnnotation(kind: .background, range: NSRange(location: 6, length: 5), selectedText: "world")

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [annotation]
    )

    let result = builder.build(text: "Hello world")
    let attributes = result.attributedString.attributes(at: 7, effectiveRange: nil)
    let bg = attributes[.backgroundColor] as? NSColor
    #expect(bg != nil)
  }

  @Test
  func testUnderlineAndBackgroundStyleApplied() {
    let annotation = makeAnnotation(kind: .underlineAndBackground, range: NSRange(location: 0, length: 11), selectedText: "Hello world")

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [annotation]
    )

    let result = builder.build(text: "Hello world")
    let attributes = result.attributedString.attributes(at: 5, effectiveRange: nil)
    #expect((attributes[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue)
    #expect((attributes[.backgroundColor] as? NSColor) != nil)
  }

  @Test
  func testMultipleAnnotations() {
    let annotations = [
      makeAnnotation(kind: .underline, range: NSRange(location: 0, length: 5), selectedText: "Hello"),
      makeAnnotation(kind: .background, range: NSRange(location: 6, length: 5), selectedText: "world"),
    ]

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: annotations
    )

    let result = builder.build(text: "Hello world")

    let helloAttrs = result.attributedString.attributes(at: 2, effectiveRange: nil)
    #expect((helloAttrs[.underlineStyle] as? Int) == NSUnderlineStyle.single.rawValue)

    let worldAttrs = result.attributedString.attributes(at: 8, effectiveRange: nil)
    #expect((worldAttrs[.backgroundColor] as? NSColor) != nil)
  }

  @Test
  func testAnnotationOutOfBoundsIsSkipped() {
    let annotation = makeAnnotation(kind: .underline, range: NSRange(location: 50, length: 10), selectedText: "overflow")

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [annotation]
    )

    let result = builder.build(text: "Short")
    // Should not crash, text is default color
    let attributes = result.attributedString.attributes(at: 0, effectiveRange: nil)
    let color = attributes[.foregroundColor] as? NSColor
    #expect(color == .labelColor)
  }
}
