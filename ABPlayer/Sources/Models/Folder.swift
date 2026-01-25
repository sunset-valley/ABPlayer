import CryptoKit
import Foundation
import SwiftData

@Model
final class Folder {
  var id: UUID
  var name: String
  var createdAt: Date

  /// 相对于根导入目录的路径，用于生成确定性 ID
  var relativePath: String

  /// 根文件夹的 security-scoped bookmark（仅根文件夹需要存储）
  @Attribute(.externalStorage)
  var bookmarkData: Data?

  @Relationship(inverse: \Folder.parent)
  var subfolders: [Folder]

  var parent: Folder?

  @Relationship(inverse: \ABFile.folder)
  var audioFiles: [ABFile]

  /// 按文件名排序的音频文件（用于播放顺序）
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

  /// 获取根文件夹
  var rootFolder: Folder {
    var root = self
    while let parent = root.parent {
      root = parent
    }
    return root
  }
}
