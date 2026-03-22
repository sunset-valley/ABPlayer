import Foundation
import Testing

@testable import ABPlayerDev

struct CrossCueTextSelectionTests {

  // MARK: - Single-cue selection

  @Test
  func testSingleCueIsCrossCueFalse() {
    let cueID = UUID()
    let selection = CrossCueTextSelection(
      segments: [
        .init(cueID: cueID, localRange: NSRange(location: 0, length: 5), text: "hello")
      ],
      fullText: "hello",
      globalRange: NSRange(location: 10, length: 5)
    )
    #expect(!selection.isCrossCue)
  }

  @Test
  func testSingleCueIDAccessor() {
    let cueID = UUID()
    let selection = CrossCueTextSelection(
      segments: [
        .init(cueID: cueID, localRange: NSRange(location: 0, length: 5), text: "hello")
      ],
      fullText: "hello",
      globalRange: NSRange(location: 0, length: 5)
    )
    #expect(selection.singleCueID == cueID)
  }

  @Test
  func testSingleLocalRange() {
    let selection = CrossCueTextSelection(
      segments: [
        .init(cueID: UUID(), localRange: NSRange(location: 3, length: 7), text: "abcdefg")
      ],
      fullText: "abcdefg",
      globalRange: NSRange(location: 3, length: 7)
    )
    #expect(selection.singleLocalRange?.location == 3)
    #expect(selection.singleLocalRange?.length == 7)
  }

  // MARK: - Cross-cue selection

  @Test
  func testCrossCueIsCrossCueTrue() {
    let selection = CrossCueTextSelection(
      segments: [
        .init(cueID: UUID(), localRange: NSRange(location: 0, length: 5), text: "Hello"),
        .init(cueID: UUID(), localRange: NSRange(location: 0, length: 3), text: " wo"),
      ],
      fullText: "Hello wo",
      globalRange: NSRange(location: 0, length: 8)
    )
    #expect(selection.isCrossCue)
  }

  @Test
  func testCrossCueSingleCueIDIsNil() {
    let selection = CrossCueTextSelection(
      segments: [
        .init(cueID: UUID(), localRange: NSRange(location: 0, length: 5), text: "Part1"),
        .init(cueID: UUID(), localRange: NSRange(location: 0, length: 5), text: "Part2"),
      ],
      fullText: "Part1Part2",
      globalRange: NSRange(location: 0, length: 10)
    )
    #expect(selection.singleCueID == nil)
    #expect(selection.singleLocalRange == nil)
  }

  @Test
  func testCrossCueSegmentCount() {
    let ids = (0..<4).map { _ in UUID() }
    let segments = ids.map {
      CrossCueTextSelection.CueSegment(cueID: $0, localRange: NSRange(location: 0, length: 2), text: "ab")
    }
    let selection = CrossCueTextSelection(
      segments: segments,
      fullText: "abababab",
      globalRange: NSRange(location: 0, length: 8)
    )
    #expect(selection.segments.count == 4)
    #expect(selection.isCrossCue)
  }

  // MARK: - Equatability

  @Test
  func testEqualityForSameValues() {
    let cueID = UUID()
    let seg = CrossCueTextSelection.CueSegment(
      cueID: cueID,
      localRange: NSRange(location: 0, length: 5),
      text: "hello"
    )
    let a = CrossCueTextSelection(
      segments: [seg],
      fullText: "hello",
      globalRange: NSRange(location: 0, length: 5)
    )
    let b = CrossCueTextSelection(
      segments: [seg],
      fullText: "hello",
      globalRange: NSRange(location: 0, length: 5)
    )
    #expect(a == b)
  }

  @Test
  func testInequalityForDifferentText() {
    let cueID = UUID()
    let a = CrossCueTextSelection(
      segments: [.init(cueID: cueID, localRange: NSRange(location: 0, length: 5), text: "hello")],
      fullText: "hello",
      globalRange: NSRange(location: 0, length: 5)
    )
    let b = CrossCueTextSelection(
      segments: [.init(cueID: cueID, localRange: NSRange(location: 0, length: 5), text: "world")],
      fullText: "world",
      globalRange: NSRange(location: 0, length: 5)
    )
    #expect(a != b)
  }

  @Test
  func testInequalityForDifferentRange() {
    let cueID = UUID()
    let a = CrossCueTextSelection(
      segments: [.init(cueID: cueID, localRange: NSRange(location: 0, length: 5), text: "hello")],
      fullText: "hello",
      globalRange: NSRange(location: 0, length: 5)
    )
    let b = CrossCueTextSelection(
      segments: [.init(cueID: cueID, localRange: NSRange(location: 0, length: 5), text: "hello")],
      fullText: "hello",
      globalRange: NSRange(location: 10, length: 5)
    )
    #expect(a != b)
  }

  // MARK: - Empty segments

  @Test
  func testEmptySegmentsNotCrossCue() {
    let selection = CrossCueTextSelection(
      segments: [],
      fullText: "",
      globalRange: NSRange(location: 0, length: 0)
    )
    #expect(!selection.isCrossCue)
    #expect(selection.singleCueID == nil)
    #expect(selection.singleLocalRange == nil)
  }
}
