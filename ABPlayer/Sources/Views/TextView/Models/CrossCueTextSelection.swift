import Foundation

/// A text selection that may span one or more subtitle cues.
///
/// When the user selects text that crosses a cue boundary in the single
/// `TranscriptTextView`, the selection is split into per-cue segments so that
/// annotations (which are stored per-cue with cue-local ranges) can be created
/// for each touched cue independently.
struct CrossCueTextSelection: Equatable, Sendable {

  // MARK: - CueSegment

  /// The portion of the selection that lies within a single cue.
  struct CueSegment: Equatable, Sendable {
    /// The cue this segment belongs to.
    let cueID: UUID
    /// Character range **relative to the start of the cue's text** (cue-local).
    let localRange: NSRange
    /// The selected text within this cue.
    let text: String
  }

  // MARK: - Properties

  /// All cue segments in document order.
  let segments: [CueSegment]

  /// The complete selected text (segments concatenated, possibly with newlines
  /// between them when the selection spans multiple cues).
  let fullText: String

  /// Character range in the unified `NSAttributedString`.
  let globalRange: NSRange

  // MARK: - Convenience

  /// `true` when the selection touches more than one cue.
  var isCrossCue: Bool { segments.count > 1 }

  /// The single cue ID when the selection is confined to one cue; `nil` for
  /// cross-cue selections.
  var singleCueID: UUID? {
    segments.count == 1 ? segments[0].cueID : nil
  }

  /// The cue-local range when the selection is confined to one cue; `nil` for
  /// cross-cue selections.
  var singleLocalRange: NSRange? {
    segments.count == 1 ? segments[0].localRange : nil
  }
}
