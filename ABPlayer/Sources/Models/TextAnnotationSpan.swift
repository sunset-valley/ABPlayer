import Foundation
import SwiftData

@Model
final class TextAnnotationSpan {
  var id: UUID
  var groupID: UUID
  var cueID: UUID
  var rangeLocation: Int
  var rangeLength: Int
  var segmentOrder: Int
  var createdAt: Date
  var updatedAt: Date

  var range: NSRange {
    NSRange(location: rangeLocation, length: rangeLength)
  }

  init(
    id: UUID = UUID(),
    groupID: UUID,
    cueID: UUID,
    rangeLocation: Int,
    rangeLength: Int,
    segmentOrder: Int,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.groupID = groupID
    self.cueID = cueID
    self.rangeLocation = rangeLocation
    self.rangeLength = rangeLength
    self.segmentOrder = segmentOrder
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
