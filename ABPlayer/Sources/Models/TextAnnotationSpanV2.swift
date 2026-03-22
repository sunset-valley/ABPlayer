import Foundation
import SwiftData

@Model
final class TextAnnotationSpanV2 {
  var id: UUID
  var groupID: UUID
  var audioFileID: UUID
  var cueID: UUID
  var cueStartTime: Double
  var cueEndTime: Double
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
    audioFileID: UUID,
    cueID: UUID,
    cueStartTime: Double,
    cueEndTime: Double,
    rangeLocation: Int,
    rangeLength: Int,
    segmentOrder: Int,
    createdAt: Date = Date(),
    updatedAt: Date = Date()
  ) {
    self.id = id
    self.groupID = groupID
    self.audioFileID = audioFileID
    self.cueID = cueID
    self.cueStartTime = cueStartTime
    self.cueEndTime = cueEndTime
    self.rangeLocation = rangeLocation
    self.rangeLength = rangeLength
    self.segmentOrder = segmentOrder
    self.createdAt = createdAt
    self.updatedAt = updatedAt
  }
}
