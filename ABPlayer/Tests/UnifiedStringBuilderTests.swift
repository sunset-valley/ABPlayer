import AppKit
import Foundation
import Testing

@testable import ABPlayer

struct UnifiedStringBuilderTests {

  // MARK: - Helpers

  private func makeCue(startTime: Double, text: String) -> SubtitleCue {
    SubtitleCue(startTime: startTime, endTime: startTime + 2.0, text: text)
  }

  private func makeBuilder(
    cues: [SubtitleCue],
    fontSize: Double = 16.0,
    activeCueID: UUID? = nil,
    annotations: [UUID: [AnnotationDisplayData]] = [:],
    colorConfig: AnnotationColorConfig = .default
  ) -> UnifiedStringBuilder {
    UnifiedStringBuilder(
      cues: cues,
      fontSize: fontSize,
      activeCueID: activeCueID,
      annotationsProvider: { cueID in annotations[cueID] ?? [] },
      colorConfig: colorConfig
    )
  }

  // MARK: - Empty / single cue

  @Test
  func testEmptyCuesProducesEmptyString() {
    let builder = makeBuilder(cues: [])
    let result = builder.build()
    #expect(result.attributedString.string.isEmpty)
    #expect(result.layouts.isEmpty)
  }

  @Test
  func testSingleCueContainsText() {
    let cue = makeCue(startTime: 1.0, text: "Hello world")
    let result = makeBuilder(cues: [cue]).build()

    #expect(result.attributedString.string.contains("Hello world"))
    #expect(result.layouts.count == 1)
  }

  @Test
  func testSingleCueTimestampPresent() {
    let cue = makeCue(startTime: 61.0, text: "Test")
    let result = makeBuilder(cues: [cue]).build()
    // 61 seconds → "1:01"
    #expect(result.attributedString.string.contains("1:01"))
  }

  @Test
  func testSingleCueLayoutRanges() {
    let text = "Hello world"
    let cue = makeCue(startTime: 1.0, text: text)
    let result = makeBuilder(cues: [cue]).build()

    guard let layout = result.layouts.first else {
      Issue.record("Expected layout"); return
    }

    // textRange should contain exactly the cue text
    let attrStr = result.attributedString.string as NSString
    let extractedText = attrStr.substring(with: layout.textRange)
    #expect(extractedText == text)
  }

  // MARK: - Multiple cues

  @Test
  func testMultipleCuesProduceConsecutiveLayouts() {
    let cues = [
      makeCue(startTime: 0, text: "First"),
      makeCue(startTime: 2, text: "Second"),
      makeCue(startTime: 4, text: "Third"),
    ]
    let result = makeBuilder(cues: cues).build()

    #expect(result.layouts.count == 3)

    // Layouts must be in document order without gaps or overlaps
    for i in 1..<result.layouts.count {
      let prev = result.layouts[i - 1]
      let curr = result.layouts[i]
      let prevEnd = prev.paragraphRange.location + prev.paragraphRange.length
      #expect(curr.paragraphRange.location == prevEnd)
    }
  }

  @Test
  func testMultipleCuesAllTextPresent() {
    let texts = ["Alpha", "Beta", "Gamma"]
    let cues = texts.enumerated().map { makeCue(startTime: Double($0.offset) * 2, text: $0.element) }
    let str = makeBuilder(cues: cues).build().attributedString.string
    for text in texts {
      #expect(str.contains(text))
    }
  }

  @Test
  func testFullStringLength() {
    let cues = [
      makeCue(startTime: 0, text: "AB"),
      makeCue(startTime: 2, text: "CD"),
    ]
    let result = makeBuilder(cues: cues).build()
    let totalLayoutLen = result.layouts.reduce(0) { $0 + $1.paragraphRange.length }
    #expect((result.attributedString.string as NSString).length == totalLayoutLen)
  }

  // MARK: - Active cue

  @Test
  func testActiveCueHasTintedBackground() {
    let cue = makeCue(startTime: 0, text: "Active")
    let result = makeBuilder(cues: [cue], activeCueID: cue.id).build()
    let layout = result.layouts[0]

    let attrStr = result.attributedString
    let attrs = attrStr.attributes(at: layout.paragraphRange.location, effectiveRange: nil)
    let bg = attrs[.backgroundColor] as? NSColor
    #expect(bg != nil)
  }

  @Test
  func testInactiveCueHasNoBackground() {
    let cue = makeCue(startTime: 0, text: "Inactive")
    let result = makeBuilder(cues: [cue], activeCueID: nil).build()
    let layout = result.layouts[0]

    let attrStr = result.attributedString
    let attrs = attrStr.attributes(at: layout.paragraphRange.location, effectiveRange: nil)
    let bg = attrs[.backgroundColor] as? NSColor
    #expect(bg == nil)
  }

  @Test
  func testOnlyActiveCueHasBackground() {
    let cue1 = makeCue(startTime: 0, text: "First")
    let cue2 = makeCue(startTime: 2, text: "Second")
    let result = makeBuilder(cues: [cue1, cue2], activeCueID: cue1.id).build()

    let layout1 = result.layouts[0]
    let layout2 = result.layouts[1]
    let attrStr = result.attributedString

    let bg1 = attrStr.attributes(at: layout1.paragraphRange.location, effectiveRange: nil)[.backgroundColor] as? NSColor
    let bg2 = attrStr.attributes(at: layout2.paragraphRange.location, effectiveRange: nil)[.backgroundColor] as? NSColor

    #expect(bg1 != nil)
    #expect(bg2 == nil)
  }

  // MARK: - Annotation colours

  @Test
  func testVocabularyAnnotationColor() {
    let cue = makeCue(startTime: 0, text: "Hello world")
    let cueID = cue.id
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .vocabulary,
      range: NSRange(location: 0, length: 5),
      selectedText: "Hello",
      comment: nil
    )
    let result = makeBuilder(cues: [cue], annotations: [cueID: [annotation]]).build()
    let layout = result.layouts[0]
    let globalAnnotStart = layout.textRange.location
    let attrs = result.attributedString.attributes(at: globalAnnotStart, effectiveRange: nil)
    let fgColor = attrs[.foregroundColor] as? NSColor
    #expect(fgColor == .systemRed)
  }

  @Test
  func testCollocationAnnotationColor() {
    let cue = makeCue(startTime: 0, text: "Hello world")
    let cueID = cue.id
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .collocation,
      range: NSRange(location: 6, length: 5),
      selectedText: "world",
      comment: nil
    )
    let result = makeBuilder(cues: [cue], annotations: [cueID: [annotation]]).build()
    let layout = result.layouts[0]
    let globalAnnotStart = layout.textRange.location + 6
    let attrs = result.attributedString.attributes(at: globalAnnotStart, effectiveRange: nil)
    let fgColor = attrs[.foregroundColor] as? NSColor
    #expect(fgColor == .systemBlue)
  }

  @Test
  func testGoodSentenceAnnotationColor() {
    let cue = makeCue(startTime: 0, text: "Great sentence here")
    let cueID = cue.id
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .goodSentence,
      range: NSRange(location: 0, length: 14),
      selectedText: "Great sentence",
      comment: nil
    )
    let result = makeBuilder(cues: [cue], annotations: [cueID: [annotation]]).build()
    let layout = result.layouts[0]
    let attrs = result.attributedString.attributes(at: layout.textRange.location, effectiveRange: nil)
    let fgColor = attrs[.foregroundColor] as? NSColor
    #expect(fgColor == .systemYellow)
  }

  @Test
  func testAnnotationHasUnderline() {
    let cue = makeCue(startTime: 0, text: "Hello")
    let cueID = cue.id
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .vocabulary,
      range: NSRange(location: 0, length: 5),
      selectedText: "Hello",
      comment: nil
    )
    let result = makeBuilder(cues: [cue], annotations: [cueID: [annotation]]).build()
    let layout = result.layouts[0]
    let attrs = result.attributedString.attributes(at: layout.textRange.location, effectiveRange: nil)
    let underline = attrs[.underlineStyle] as? Int
    #expect(underline == NSUnderlineStyle.single.rawValue)
  }

  @Test
  func testOutOfBoundsAnnotationSkipped() {
    let cue = makeCue(startTime: 0, text: "Hi")
    let cueID = cue.id
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .vocabulary,
      range: NSRange(location: 100, length: 10),
      selectedText: "overflow",
      comment: nil
    )
    // Should not crash
    let result = makeBuilder(cues: [cue], annotations: [cueID: [annotation]]).build()
    #expect(result.layouts.count == 1)
    let layout = result.layouts[0]
    let attrs = result.attributedString.attributes(at: layout.textRange.location, effectiveRange: nil)
    let fgColor = attrs[.foregroundColor] as? NSColor
    // Default secondary colour — not annotation red
    #expect(fgColor != .systemRed)
  }

  @Test
  func testCustomColorConfig() {
    let cue = makeCue(startTime: 0, text: "Test")
    let cueID = cue.id
    let annotation = AnnotationDisplayData(
      id: UUID(),
      type: .vocabulary,
      range: NSRange(location: 0, length: 4),
      selectedText: "Test",
      comment: nil
    )
    let customConfig = AnnotationColorConfig(
      vocabulary: .systemOrange,
      collocation: .systemGreen,
      goodSentence: .systemPurple
    )
    let result = makeBuilder(
      cues: [cue],
      annotations: [cueID: [annotation]],
      colorConfig: customConfig
    ).build()
    let layout = result.layouts[0]
    let attrs = result.attributedString.attributes(at: layout.textRange.location, effectiveRange: nil)
    let fgColor = attrs[.foregroundColor] as? NSColor
    #expect(fgColor == .systemOrange)
  }

  // MARK: - Font

  @Test
  func testFontSizeApplied() {
    let cue = makeCue(startTime: 0, text: "Size test")
    let result = makeBuilder(cues: [cue], fontSize: 20.0).build()
    let layout = result.layouts[0]
    let attrs = result.attributedString.attributes(at: layout.textRange.location, effectiveRange: nil)
    if let font = attrs[.font] as? NSFont {
      #expect(abs(font.pointSize - 20.0) < 0.01)
    } else {
      Issue.record("Font attribute missing")
    }
  }

  // MARK: - Layout CueID mapping

  @Test
  func testLayoutCueIDsMatchInput() {
    let cues = [
      makeCue(startTime: 0, text: "A"),
      makeCue(startTime: 2, text: "B"),
      makeCue(startTime: 4, text: "C"),
    ]
    let result = makeBuilder(cues: cues).build()
    let layoutIDs = result.layouts.map(\.cueID)
    let inputIDs = cues.map(\.id)
    #expect(layoutIDs == inputIDs)
  }

  // MARK: - Timestamp format

  @Test
  func testZeroTimestamp() {
    let cue = makeCue(startTime: 0, text: "Zero")
    let str = makeBuilder(cues: [cue]).build().attributedString.string
    #expect(str.contains("0:00"))
  }

  @Test
  func testMinuteTimestamp() {
    let cue = makeCue(startTime: 90, text: "Ninety")  // 1:30
    let str = makeBuilder(cues: [cue]).build().attributedString.string
    #expect(str.contains("1:30"))
  }
}
