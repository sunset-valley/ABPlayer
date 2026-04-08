import Foundation
import SwiftUI
import Observation

/// User configurable library settings
@MainActor
@Observable
public final class LibrarySettings {
  public init() {}

  private var scopedLibraryURL: URL?
  private var isLibraryAccessActive = false

  /// Path to the media library
  @ObservationIgnored
  @AppStorage("library_path") private var _libraryPath: String = ""
  public var libraryPath: String {
    get { access(keyPath: \.libraryPath); return _libraryPath }
    set { withMutation(keyPath: \.libraryPath) { _libraryPath = newValue } }
  }

  @ObservationIgnored
  @AppStorage("library_bookmark") private var _libraryBookmarkData: Data = Data()

  var libraryBookmarkData: Data? {
    get {
      let data = _libraryBookmarkData
      return data.isEmpty ? nil : data
    }
    set {
      _libraryBookmarkData = newValue ?? Data()
    }
  }

  /// Returns the library directory URL (user-specified or default)
  public var libraryDirectoryURL: URL {
    if libraryPath.isEmpty {
      return LibrarySettings.defaultLibraryDirectory
    }
    return URL(fileURLWithPath: libraryPath)
  }

  public static var defaultLibraryDirectory: URL {
    let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
    let baseURL = appSupport.first ?? FileManager.default.homeDirectoryForCurrentUser
    let folderName = Bundle.main.bundleIdentifier ?? "ABPlayer"
    return baseURL
      .appendingPathComponent(folderName, isDirectory: true)
      .appendingPathComponent("Library", isDirectory: true)
  }

  func setLibraryDirectory(_ url: URL) throws {
    let didStartAccessing = url.startAccessingSecurityScopedResource()
    defer {
      if didStartAccessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    do {
      let bookmarkData = try url.bookmarkData(
        options: [.withSecurityScope],
        includingResourceValuesForKeys: nil,
        relativeTo: nil
      )
      libraryPath = url.path
      libraryBookmarkData = bookmarkData
    } catch {
      if Self.isInsideUserHomeDirectory(url) {
        libraryPath = url.path
        libraryBookmarkData = nil
        endLibraryAccessSession()
        return
      }
      throw error
    }

    beginLibraryAccessSession()
  }

  func withLibraryAccess<T>(_ operation: () async throws -> T) async throws -> T {
    alignLibraryAccessSessionWithCurrentPath()

    if isLibraryAccessActive {
      return try await operation()
    }

    guard !libraryPath.isEmpty else {
      return try await operation()
    }

    do {
      if let scopedURL = try resolveScopedLibraryURL(),
        scopedURL.startAccessingSecurityScopedResource()
      {
        defer {
          scopedURL.stopAccessingSecurityScopedResource()
        }
        return try await operation()
      }
    } catch {
      // Fall back to direct file-system access.
      // If permission is insufficient, the downstream operation will still throw.
    }

    return try await operation()
  }

  func beginLibraryAccessSession() {
    guard !libraryPath.isEmpty else {
      endLibraryAccessSession()
      return
    }

    if isLibraryAccessActive,
      let scopedLibraryURL,
      scopedLibraryURL.standardizedFileURL.path == libraryDirectoryURL.standardizedFileURL.path
    {
      return
    }

    endLibraryAccessSession()

    do {
      if let scopedURL = try resolveScopedLibraryURL(),
        scopedURL.startAccessingSecurityScopedResource()
      {
        scopedLibraryURL = scopedURL
        isLibraryAccessActive = true
      }
    } catch {
      scopedLibraryURL = nil
      isLibraryAccessActive = false
    }
  }

  func endLibraryAccessSession() {
    if let scopedLibraryURL, isLibraryAccessActive {
      scopedLibraryURL.stopAccessingSecurityScopedResource()
    }

    scopedLibraryURL = nil
    isLibraryAccessActive = false
  }

  func mediaFileURL(for audioFile: ABFile) -> URL {
    libraryDirectoryURL.appendingPathComponent(audioFile.relativePath)
  }

  func mediaFileURL(forRelativePath relativePath: String) -> URL {
    libraryDirectoryURL.appendingPathComponent(relativePath)
  }

  func pdfFileURL(for audioFile: ABFile) -> URL {
    mediaFileURL(for: audioFile)
      .deletingPathExtension()
      .appendingPathExtension(FolderImporter.pdfExtension)
  }

  func subtitleFileURL(for audioFile: ABFile) -> URL {
    mediaFileURL(for: audioFile)
      .deletingPathExtension()
      .appendingPathExtension("srt")
  }

  public func ensureLibraryDirectoryExists() throws {
    let fileManager = FileManager.default
    let url = libraryDirectoryURL

    if !fileManager.fileExists(atPath: url.path) {
      try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
    }
  }

  public func isInLibrary(_ url: URL) -> Bool {
    let libraryURL = libraryDirectoryURL
      .resolvingSymlinksInPath()
      .standardizedFileURL
    let candidateURL = url
      .resolvingSymlinksInPath()
      .standardizedFileURL

    let libraryPath = libraryURL.path
    let candidatePath = candidateURL.path

    if candidatePath == libraryPath {
      return true
    }

    let normalizedLibraryPath = libraryPath.hasSuffix("/") ? libraryPath : libraryPath + "/"
    return candidatePath.hasPrefix(normalizedLibraryPath)
  }

  private func resolveScopedLibraryURL() throws -> URL? {
    if let bookmarkData = libraryBookmarkData {
      var isStale = false
      let scopedURL = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if isStale {
        libraryBookmarkData = try scopedURL.bookmarkData(
          options: [.withSecurityScope],
          includingResourceValuesForKeys: nil,
          relativeTo: nil
        )
      }

      return scopedURL
    }

    let url = libraryDirectoryURL
    if let newBookmark = try? url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    ) {
      libraryBookmarkData = newBookmark
      var isStale = false
      return try URL(
        resolvingBookmarkData: newBookmark,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )
    }

    return nil
  }

  private func alignLibraryAccessSessionWithCurrentPath() {
    guard isLibraryAccessActive, let scopedLibraryURL else {
      return
    }

    let activePath = scopedLibraryURL.standardizedFileURL.path
    let targetPath = libraryDirectoryURL.standardizedFileURL.path
    if activePath != targetPath {
      endLibraryAccessSession()
      beginLibraryAccessSession()
    }
  }

  private static func isInsideUserHomeDirectory(_ url: URL) -> Bool {
    let homePath = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL.path
    let candidatePath = url.standardizedFileURL.path
    return candidatePath == homePath || candidatePath.hasPrefix(homePath + "/")
  }
}
