import CryptoKit
import Foundation
import SwiftData

enum FileType: String, Codable {
  case audio
  case video
  
  var iconName: String {
    switch self {
    case .audio:
      return "music.note"
    case .video:
      return "movieclapper"
    }
  }
}

@Model
final class ABFile {
  var id: UUID
  var displayName: String
  var fileType: FileType

  @Attribute(.externalStorage)
  var bookmarkData: Data

  var createdAt: Date

  @Relationship(inverse: \LoopSegment.audioFile)
  var segments: [LoopSegment]

  /// Playback record (cascade delete)
  @Relationship(deleteRule: .cascade, inverse: \PlaybackRecord.audioFile)
  var playbackRecord: PlaybackRecord?

  /// Convenience accessor for current playback position
  var currentPlaybackPosition: Double {
    get { playbackRecord?.currentPosition ?? 0 }
    set {
      if playbackRecord == nil {
        playbackRecord = PlaybackRecord()
      }
      playbackRecord?.currentPosition = newValue
    }
  }

  /// Parent folder
  var folder: Folder?

  /// Path relative to the imported root folder (including file name)
  var relativePath: String = ""

  /// Related subtitle file
  @Relationship(inverse: \SubtitleFile.audioFile)
  var subtitleFile: SubtitleFile?

  /// Related PDF bookmark
  @Attribute(.externalStorage)
  var pdfBookmarkData: Data?

  /// Cached media duration in seconds to avoid repeated reads
  var cachedDuration: Double?

  /// Whether a transcription record exists in the database
  var hasTranscriptionRecord: Bool = false

  /// Loading error message
  var loadError: String?

  init(
    id: UUID = UUID(),
    displayName: String,
    fileType: FileType? = nil,
    bookmarkData: Data,
    createdAt: Date = Date(),
    segments: [LoopSegment] = [],
    folder: Folder? = nil,
    relativePath: String = "",
    subtitleFile: SubtitleFile? = nil,
    pdfBookmarkData: Data? = nil,
    cachedDuration: Double? = nil,
    hasTranscriptionRecord: Bool = false,
    loadError: String? = nil
  ) {
    self.id = id
    self.fileType = fileType ?? Self.inferFileType(from: displayName)
    self.displayName = (displayName as NSString).deletingPathExtension
    self.bookmarkData = bookmarkData
    self.createdAt = createdAt
    self.segments = segments
    self.folder = folder
    self.relativePath = relativePath
    self.subtitleFile = subtitleFile
    self.pdfBookmarkData = pdfBookmarkData
    self.cachedDuration = cachedDuration
    self.hasTranscriptionRecord = hasTranscriptionRecord
    self.loadError = loadError
  }
}

@Model
final class LoopSegment {
  var id: UUID
  var label: String
  var startTime: Double
  var endTime: Double
  var index: Int
  var createdAt: Date
  var audioFile: ABFile?

  init(
    id: UUID = UUID(),
    label: String,
    startTime: Double,
    endTime: Double,
    index: Int,
    createdAt: Date = Date(),
    audioFile: ABFile? = nil
  ) {
    self.id = id
    self.label = label
    self.startTime = startTime
    self.endTime = endTime
    self.index = index
    self.createdAt = createdAt
    self.audioFile = audioFile
  }
}

extension ABFile {
  static func generateDeterministicID(from relativePath: String) -> UUID {
    DeterministicID.generate(from: relativePath)
  }

  var srtFileURL: URL? {
    guard let audioURL = resolvedURL() else { return nil }
    return audioURL.deletingPathExtension().appendingPathExtension("srt")
  }

  func resolvedURL() -> URL? {
    try? resolveURL()
  }

  func resolvedPDFURL() -> URL? {
    guard let pdfBookmarkData else { return nil }
    var isStale = false
    return try? URL(
      resolvingBookmarkData: pdfBookmarkData,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
  }

  private func resolveURL() throws -> URL {
    var isStale = false
    return try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )
  }

  /// Checks whether the bookmark is still valid (file exists)
  var isBookmarkValid: Bool {
    guard let url = resolvedURL() else { return false }
    return FileManager.default.fileExists(atPath: url.path)
  }

  static let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv"]

  static func inferFileType(from displayName: String) -> FileType {
    let ext = (displayName as NSString).pathExtension.lowercased()
    return videoExtensions.contains(ext) ? .video : .audio
  }

  var isVideo: Bool {
    fileType == .video
  }
}
