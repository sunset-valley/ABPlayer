import Foundation

/// Maps a subtitle cue to its character range in the unified NSAttributedString.
///
/// Character positions are UTF-16 code-unit offsets compatible with NSRange /
/// NSAttributedString / NSTextView APIs.
struct CueLayout: Equatable, Sendable {
  let cueID: UUID
  let endTime: Double
  let startTime: Double
  let cueText: String

  /// Range of the "timestamp\t" prefix in the unified string.
  let prefixRange: NSRange

  /// Range of the cue's plain text content (no prefix, no trailing newline).
  let textRange: NSRange

  /// Full paragraph range: prefix + text + trailing newline.
  let paragraphRange: NSRange

  // MARK: - Range Conversion

  /// Returns the cue-local range (relative to the start of `cueText`) for the
  /// portion of `globalRange` that falls inside `textRange`, or `nil` if there
  /// is no overlap.
  func localRange(from globalRange: NSRange) -> NSRange? {
    let intersection = NSIntersectionRange(globalRange, textRange)
    guard intersection.length > 0 else { return nil }
    return NSRange(
      location: intersection.location - textRange.location,
      length: intersection.length
    )
  }

  /// Returns the global range in the unified string for a cue-local range.
  func globalRange(from localRange: NSRange) -> NSRange {
    NSRange(
      location: textRange.location + localRange.location,
      length: localRange.length
    )
  }

  /// Returns `true` when `charIndex` falls inside the text content of this cue
  /// (not inside the prefix or newline).
  func containsTextIndex(_ charIndex: Int) -> Bool {
    charIndex >= textRange.location
      && charIndex < textRange.location + textRange.length
  }

}
