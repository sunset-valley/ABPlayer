import Foundation
import SwiftData

@Model
final class TextAnnotationGroup {
  var id: UUID
  var stylePresetID: UUID
  var selectedTextSnapshot: String
  var comment: String?
  var createdAt: Date
  var updatedAt: Date

  init(
    id: UUID = UUID(),
    stylePresetID: UUID,
    selectedTextSnapshot: String,
    comment: String? = nil,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.stylePresetID = stylePresetID
    self.selectedTextSnapshot = selectedTextSnapshot
    self.comment = comment
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
