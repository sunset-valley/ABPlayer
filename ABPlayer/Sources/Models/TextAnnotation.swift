import Foundation
import SwiftData

/// Type of text annotation in subtitle cues
enum AnnotationType: String, Codable, CaseIterable, Sendable {
  /// 生词 - New/difficult vocabulary word
  case vocabulary
  /// 固定搭配 - Fixed collocation or phrase
  case collocation
  /// 好句子 - Good sentence worth noting
  case goodSentence
}

/// Persistent model for text annotations on subtitle cues
@Model
final class TextAnnotation {
  var id: UUID

  /// The subtitle cue ID this annotation belongs to
  var cueID: UUID

  /// Character range start in the cue's text
  var rangeLocation: Int

  /// Character range length in the cue's text
  var rangeLength: Int

  /// Annotation type raw value
  var typeRawValue: String

  /// The selected text content (denormalized for display/search)
  var selectedText: String

  /// User comment/note
  var comment: String?

  var createdAt: Date
  var updatedAt: Date

  /// Computed annotation type
  var type: AnnotationType {
    get { AnnotationType(rawValue: typeRawValue) ?? .vocabulary }
    set { typeRawValue = newValue.rawValue }
  }

  /// Computed NSRange
  var range: NSRange {
    NSRange(location: rangeLocation, length: rangeLength)
  }

  init(
    id: UUID = UUID(),
    cueID: UUID,
    rangeLocation: Int,
    rangeLength: Int,
    type: AnnotationType,
    selectedText: String,
    comment: String? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.cueID = cueID
    self.rangeLocation = rangeLocation
    self.rangeLength = rangeLength
    self.typeRawValue = type.rawValue
    self.selectedText = selectedText
    self.comment = comment
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
