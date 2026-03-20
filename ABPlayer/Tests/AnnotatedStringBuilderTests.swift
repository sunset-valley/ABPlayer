import AppKit
import Foundation
import Testing

@testable import ABPlayer

struct AnnotatedStringBuilderTests {

  @Test
  func testPlainTextNoAnnotations() {
    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [],
      colorConfig: .default
    )

    let result = builder.build(text: "Hello world test")
    #expect(result.attributedString.string == "Hello world test")
  }

  @Test
  func testEmptyText() {
    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [],
      colorConfig: .default
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
      annotations: [],
      colorConfig: .default
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
      annotations: [],
      colorConfig: .default
    )

    let result = builder.build(text: "Hello")
    let attributes = result.attributedString.attributes(at: 0, effectiveRange: nil)
    let color = attributes[.foregroundColor] as? NSColor
    #expect(color == .labelColor)
  }

  @Test
  func testSingleVocabularyAnnotation() {
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .vocabulary,
      range: NSRange(location: 0, length: 5),
      selectedText: "Hello",
      comment: nil
    )

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [annotation],
      colorConfig: .default
    )

    let result = builder.build(text: "Hello world")
    let attributes = result.attributedString.attributes(at: 2, effectiveRange: nil)

    // Vocabulary annotation should apply red color
    let fgColor = attributes[.foregroundColor] as? NSColor
    #expect(fgColor == .systemRed)

    // Should have underline
    let underline = attributes[.underlineStyle] as? Int
    #expect(underline == NSUnderlineStyle.single.rawValue)

    // Non-annotated text should remain default
    let normalAttributes = result.attributedString.attributes(at: 6, effectiveRange: nil)
    let normalColor = normalAttributes[.foregroundColor] as? NSColor
    #expect(normalColor == .labelColor)
  }

  @Test
  func testCollocationAnnotation() {
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .collocation,
      range: NSRange(location: 6, length: 5),
      selectedText: "world",
      comment: nil
    )

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [annotation],
      colorConfig: .default
    )

    let result = builder.build(text: "Hello world")
    let attributes = result.attributedString.attributes(at: 7, effectiveRange: nil)
    let color = attributes[.foregroundColor] as? NSColor
    #expect(color == .systemBlue)
  }

  @Test
  func testGoodSentenceAnnotation() {
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .goodSentence,
      range: NSRange(location: 0, length: 11),
      selectedText: "Hello world",
      comment: nil
    )

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [annotation],
      colorConfig: .default
    )

    let result = builder.build(text: "Hello world")
    let attributes = result.attributedString.attributes(at: 5, effectiveRange: nil)
    let color = attributes[.foregroundColor] as? NSColor
    #expect(color == .systemYellow)
  }

  @Test
  func testMultipleAnnotations() {
    let annotations = [
      AnnotationDisplayData(
        id: UUID(), type: .vocabulary,
        range: NSRange(location: 0, length: 5),
        selectedText: "Hello", comment: nil
      ),
      AnnotationDisplayData(
        id: UUID(), type: .collocation,
        range: NSRange(location: 6, length: 5),
        selectedText: "world", comment: nil
      ),
    ]

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: annotations,
      colorConfig: .default
    )

    let result = builder.build(text: "Hello world")

    let helloAttrs = result.attributedString.attributes(at: 2, effectiveRange: nil)
    #expect((helloAttrs[.foregroundColor] as? NSColor) == .systemRed)

    let worldAttrs = result.attributedString.attributes(at: 8, effectiveRange: nil)
    #expect((worldAttrs[.foregroundColor] as? NSColor) == .systemBlue)
  }

  @Test
  func testCustomColorConfig() {
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .vocabulary,
      range: NSRange(location: 0, length: 5),
      selectedText: "Hello",
      comment: nil
    )

    let customConfig = AnnotationColorConfig(
      vocabulary: .systemOrange,
      collocation: .systemGreen,
      goodSentence: .systemPurple
    )

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [annotation],
      colorConfig: customConfig
    )

    let result = builder.build(text: "Hello world")
    let attributes = result.attributedString.attributes(at: 2, effectiveRange: nil)
    let color = attributes[.foregroundColor] as? NSColor
    #expect(color == .systemOrange)
  }

  @Test
  func testAnnotationOutOfBoundsIsSkipped() {
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .vocabulary,
      range: NSRange(location: 50, length: 10),
      selectedText: "overflow",
      comment: nil
    )

    let builder = AnnotatedStringBuilder(
      fontSize: 16.0,
      defaultTextColor: .labelColor,
      annotations: [annotation],
      colorConfig: .default
    )

    let result = builder.build(text: "Short")
    // Should not crash, text is default color
    let attributes = result.attributedString.attributes(at: 0, effectiveRange: nil)
    let color = attributes[.foregroundColor] as? NSColor
    #expect(color == .labelColor)
  }
}
