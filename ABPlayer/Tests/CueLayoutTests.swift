import Foundation
import Testing

@testable import ABPlayerDev

struct CueLayoutTests {

  private func makeLayout(
    offset: Int = 0,
    prefixLen: Int = 6,
    textLen: Int = 20
  ) -> CueLayout {
    let prefixRange = NSRange(location: offset, length: prefixLen)
    let textRange = NSRange(location: offset + prefixLen, length: textLen)
    let paragraphRange = NSRange(location: offset, length: prefixLen + textLen + 1)  // +1 for \n
    return CueLayout(
      cueID: UUID(),
      startTime: 1.0,
      cueText: String(repeating: "x", count: textLen),
      prefixRange: prefixRange,
      textRange: textRange,
      paragraphRange: paragraphRange
    )
  }

  // MARK: - localRange(from:)

  @Test
  func testLocalRangeFullOverlap() {
    let layout = makeLayout(offset: 10, prefixLen: 5, textLen: 20)
    // textRange = 15..<35
    let globalRange = NSRange(location: 15, length: 20)
    let local = layout.localRange(from: globalRange)
    #expect(local?.location == 0)
    #expect(local?.length == 20)
  }

  @Test
  func testLocalRangePartialOverlap() {
    let layout = makeLayout(offset: 10, prefixLen: 5, textLen: 20)
    // textRange = 15..<35; global 20..<30 ∩ 15..<35 = 20..<30
    let globalRange = NSRange(location: 20, length: 10)
    let local = layout.localRange(from: globalRange)
    // local location = 20 - 15 = 5
    #expect(local?.location == 5)
    #expect(local?.length == 10)
  }

  @Test
  func testLocalRangeNoOverlap() {
    let layout = makeLayout(offset: 10, prefixLen: 5, textLen: 20)
    // textRange = 15..<35; globalRange = 0..<5 (inside prefix, no text overlap)
    let globalRange = NSRange(location: 0, length: 5)
    #expect(layout.localRange(from: globalRange) == nil)
  }

  @Test
  func testLocalRangeCrossesPrefixAndText() {
    let layout = makeLayout(offset: 0, prefixLen: 6, textLen: 20)
    // textRange = 6..<26; globalRange = 0..<26 (starts in prefix, ends at text end)
    // intersection with textRange = 6..<26 → length 20, local 0
    let globalRange = NSRange(location: 0, length: 26)
    let local = layout.localRange(from: globalRange)
    #expect(local?.location == 0)
    #expect(local?.length == 20)
  }

  // MARK: - globalRange(from:)

  @Test
  func testGlobalRangeConversion() {
    let layout = makeLayout(offset: 100, prefixLen: 5, textLen: 30)
    // textRange starts at 105
    let localRange = NSRange(location: 5, length: 10)
    let global = layout.globalRange(from: localRange)
    #expect(global.location == 110)
    #expect(global.length == 10)
  }

  @Test
  func testGlobalRangeAtStart() {
    let layout = makeLayout(offset: 50, prefixLen: 4, textLen: 15)
    let localRange = NSRange(location: 0, length: 15)
    let global = layout.globalRange(from: localRange)
    #expect(global.location == 54)
    #expect(global.length == 15)
  }

  // MARK: - containsTextIndex

  @Test
  func testContainsTextIndexInsideText() {
    let layout = makeLayout(offset: 0, prefixLen: 5, textLen: 20)
    // textRange = 5..<25
    #expect(layout.containsTextIndex(5))
    #expect(layout.containsTextIndex(14))
    #expect(layout.containsTextIndex(24))
  }

  @Test
  func testContainsTextIndexInPrefix() {
    let layout = makeLayout(offset: 0, prefixLen: 5, textLen: 20)
    // prefix = 0..<5
    #expect(!layout.containsTextIndex(0))
    #expect(!layout.containsTextIndex(4))
  }

  @Test
  func testContainsTextIndexAtNewline() {
    let layout = makeLayout(offset: 0, prefixLen: 5, textLen: 20)
    // newline at index 25
    #expect(!layout.containsTextIndex(25))
  }

  // MARK: - Round-trip

  @Test
  func testLocalGlobalRoundTrip() {
    let layout = makeLayout(offset: 20, prefixLen: 6, textLen: 30)
    let originalLocal = NSRange(location: 3, length: 12)
    let global = layout.globalRange(from: originalLocal)
    let backToLocal = layout.localRange(from: global)
    #expect(backToLocal?.location == originalLocal.location)
    #expect(backToLocal?.length == originalLocal.length)
  }
}
