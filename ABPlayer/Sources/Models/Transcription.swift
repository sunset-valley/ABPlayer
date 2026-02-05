import Foundation
import SwiftData

/// Cached transcription data for an audio file
@Model
final class Transcription {
  var id: UUID

  /// Audio file identifier (using AudioFile's UUID)
  var audioFileId: String

  /// Original audio file name for display
  var audioFileName: String

  /// Transcription creation date
  var createdAt: Date

  /// WhisperKit model used for transcription
  var modelUsed: String

  /// Language detected or specified
  var language: String?

  init(
    audioFileId: String,
    audioFileName: String,
    modelUsed: String = "distil-large-v3",
    language: String? = nil
  ) {
    self.id = UUID()
    self.audioFileId = audioFileId
    self.audioFileName = audioFileName
    self.createdAt = Date()
    self.modelUsed = modelUsed
    self.language = language
  }
}
