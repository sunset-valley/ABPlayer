import CryptoKit
import Foundation
import SwiftData
import UniformTypeIdentifiers

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
  /// Legacy field kept for store compatibility.
  /// Managed-library mode no longer uses per-file bookmarks for access.
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
  /// Legacy field kept for store compatibility.
  /// PDF is now derived from sibling path (<media basename>.pdf) in library.
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

  /// Legacy helper retained for API compatibility.
  /// Managed-library mode derives subtitle URL from sibling `.srt` path.
  var srtFileURL: URL? {
    nil
  }

  /// Legacy helper retained for compatibility with old call sites.
  /// New code should resolve media URLs via LibrarySettings + relativePath.
  func resolvedURL() -> URL? {
    nil
  }

  /// Legacy helper retained for compatibility with old call sites.
  /// New code should derive PDF URL from sibling `.pdf` path.
  func resolvedPDFURL() -> URL? {
    nil
  }

  /// Legacy compatibility flag.
  /// In managed-library mode, actual file existence is checked by services using LibrarySettings.
  var isBookmarkValid: Bool {
    !relativePath.isEmpty
  }

  static func inferFileType(from displayName: String) -> FileType {
    let ext = (displayName as NSString).pathExtension.lowercased()
    guard !ext.isEmpty,
      let type = UTType(filenameExtension: ext)
    else {
      return .audio
    }

    return type.conforms(to: .movie) ? .video : .audio
  }

  static func inferFileType(from url: URL) -> FileType {
    if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
      if contentType.conforms(to: .movie) {
        return .video
      }
      if contentType.conforms(to: .audio) {
        return .audio
      }
    }

    return inferFileType(from: url.lastPathComponent)
  }

  var isVideo: Bool {
    fileType == .video
  }

  var playbackProgress: Double? {
    guard currentPlaybackPosition > 0, let cachedDuration, cachedDuration > 0 else {
      return nil
    }

    return min(max(currentPlaybackPosition / cachedDuration, 0), 1)
  }
}
