import CryptoKit
import Foundation
import SwiftData

@Model
final class Folder {
  var id: UUID
  var name: String
  var createdAt: Date

  /// Path relative to the imported root folder, used for deterministic IDs
  var relativePath: String

  /// Security-scoped bookmark for root folders (stored only for roots)
  @Attribute(.externalStorage)
  var bookmarkData: Data?

  @Relationship(inverse: \Folder.parent)
  var subfolders: [Folder]

  var parent: Folder?

  @Relationship(inverse: \ABFile.folder)
  var audioFiles: [ABFile]

  /// Audio files sorted by file name (used for playback order)
  var sortedAudioFiles: [ABFile] {
    audioFiles.sorted { $0.displayName < $1.displayName }
  }

  init(
    id: UUID = UUID(),
    name: String,
    relativePath: String = "",
    createdAt: Date = Date(),
    parent: Folder? = nil,
    subfolders: [Folder] = [],
    audioFiles: [ABFile] = [],
    bookmarkData: Data? = nil
  ) {
    self.id = id
    self.name = name
    self.relativePath = relativePath
    self.createdAt = createdAt
    self.parent = parent
    self.subfolders = subfolders
    self.audioFiles = audioFiles
    self.bookmarkData = bookmarkData
  }
}

extension Folder {
  static func generateDeterministicID(from relativePath: String) -> UUID {
    DeterministicID.generate(from: relativePath)
  }

  func resolveURL() throws -> URL? {
    guard let bookmarkData else { return nil }

    var isStale = false
    let url = try URL(
      resolvingBookmarkData: bookmarkData,
      options: [.withSecurityScope],
      relativeTo: nil,
      bookmarkDataIsStale: &isStale
    )

    return url
  }
}
