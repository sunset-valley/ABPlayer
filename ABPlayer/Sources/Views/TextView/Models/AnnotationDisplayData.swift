import Foundation

/// Value type for passing annotation data to views
struct AnnotationDisplayData: Identifiable, Equatable, Sendable {
  let id: UUID
  let type: AnnotationType
  let range: NSRange
  let selectedText: String
  let comment: String?

  init(
    id: UUID,
    type: AnnotationType,
    range: NSRange,
    selectedText: String,
    comment: String?
  ) {
    self.id = id
    self.type = type
    self.range = range
    self.selectedText = selectedText
    self.comment = comment
  }

  init(from annotation: TextAnnotation) {
    self.id = annotation.id
    self.type = annotation.type
    self.range = annotation.range
    self.selectedText = annotation.selectedText
    self.comment = annotation.comment
  }
}
