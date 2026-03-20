import Foundation
import SwiftData

@Model
final class PlaybackRecord {
  var id: UUID

  /// Last playback timestamp
  var lastPlayedAt: Date?

  /// Number of completed playbacks
  var completionCount: Int

  /// Current playback position in seconds
  var currentPosition: Double

  /// Related audio file
  var audioFile: ABFile?

  init(
    id: UUID = UUID(),
    lastPlayedAt: Date? = nil,
    completionCount: Int = 0,
    currentPosition: Double = 0,
    audioFile: ABFile? = nil
  ) {
    self.id = id
    self.lastPlayedAt = lastPlayedAt
    self.completionCount = completionCount
    self.currentPosition = currentPosition
    self.audioFile = audioFile
  }
}
