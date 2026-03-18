import Foundation

extension URL {
  /// Returns a URL that doesn't conflict with any existing file by appending a counter suffix.
  static func uniqueURL(for url: URL) -> URL {
    let fileManager = FileManager.default
    guard fileManager.fileExists(atPath: url.path) else { return url }

    let directory = url.deletingLastPathComponent()
    let baseName = url.deletingPathExtension().lastPathComponent
    let fileExtension = url.pathExtension

    var counter = 1
    var candidate = url

    while fileManager.fileExists(atPath: candidate.path) {
      let newName = "\(baseName) \(counter)"
      if fileExtension.isEmpty {
        candidate = directory.appendingPathComponent(newName)
      } else {
        candidate = directory.appendingPathComponent(newName).appendingPathExtension(fileExtension)
      }
      counter += 1
    }

    return candidate
  }
}
