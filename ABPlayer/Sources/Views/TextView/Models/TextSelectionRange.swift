import Foundation

/// Represents a user's text selection within a subtitle cue
struct TextSelectionRange: Equatable, Sendable {
  let cueID: UUID
  let range: NSRange
  let selectedText: String
}
