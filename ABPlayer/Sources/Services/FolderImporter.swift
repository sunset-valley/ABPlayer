import AVFoundation
import Foundation
import OSLog
import SwiftData
import UniformTypeIdentifiers

/// Handles recursive folder import with automatic file pairing
/// Supports idempotent sync operations (safe to call multiple times)
@MainActor
final class FolderImporter {
  private let modelContext: ModelContext
  private let librarySettings: LibrarySettings

  init(modelContext: ModelContext, librarySettings: LibrarySettings) {
    self.modelContext = modelContext
    self.librarySettings = librarySettings
  }

  static let subtitleExtensions: Set<String> = ["srt", "vtt"]
  static let pdfExtension = "pdf"

  // MARK: - Public API

  /// Syncs a folder (supports first import and rescans)
  /// - Parameter url: Root folder URL
  /// - Returns: Root `Folder` ID after sync
  func syncFolder(
    at url: URL,
    parentFolder: Folder?,
    copyExternalIntoLibrary: Bool = true,
    onProgressMessage: (@MainActor (String) -> Void)? = nil
  ) async throws -> PersistentIdentifier? {
    let alreadyInLibrary = librarySettings.isInLibrary(url)
    let needsCopyIntoLibrary = !alreadyInLibrary && copyExternalIntoLibrary

    // Library-internal URLs don't carry a security-scoped bookmark;
    // the app already has natural access to Application Support.
    if needsCopyIntoLibrary {
      guard url.startAccessingSecurityScopedResource() else {
        throw ImportError.accessDenied
      }
    }

    defer {
      if needsCopyIntoLibrary {
        url.stopAccessingSecurityScopedResource()
      }
    }

    try librarySettings.ensureLibraryDirectoryExists()

    let destinationURL: URL
    if needsCopyIntoLibrary {
      let destinationDirectory = folderLibraryURL(for: parentFolder) ?? librarySettings.libraryDirectoryURL
      destinationURL = try copyItemToLibrary(from: url, destinationDirectory: destinationDirectory)
    } else {
      destinationURL = url
    }

    let libraryURL = librarySettings.libraryDirectoryURL.standardizedFileURL
    let rootPath = String(
      destinationURL.standardizedFileURL.path
        .dropFirst(libraryURL.path.count)
        .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
    )
    let folder = try await processDirectory(
      at: destinationURL,
      relativePath: rootPath,
      parent: parentFolder,
      onProgressMessage: onProgressMessage
    )

    try modelContext.save()

    return folder.persistentModelID
  }

  // MARK: - Directory Processing

  /// Processes a directory recursively
  private func processDirectory(
    at url: URL,
    relativePath: String,
    parent: Folder?,
    onProgressMessage: (@MainActor (String) -> Void)?
  ) async throws
    -> Folder
  {
    onProgressMessage?("Scanning \(url.lastPathComponent)...")

    let folder = findOrCreateFolder(at: url, relativePath: relativePath)

    // Set parent-child relationship when needed
    if let parent = parent, folder.parent?.id != parent.id {
      folder.parent = parent
      if !parent.subfolders.contains(where: { $0.id == folder.id }) {
        parent.subfolders.append(folder)
      }
    }

    let fileManager = FileManager.default
    let contents = try fileManager.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    // Classify files
    var directories: [URL] = []
    var mediaFiles: [URL] = []
    var subtitleFiles: [URL] = []
    var pdfFiles: [URL] = []

    for item in contents {
      let resourceValues = try item.resourceValues(forKeys: [.isDirectoryKey])

      if resourceValues.isDirectory == true {
        directories.append(item)
      } else {
        let ext = item.pathExtension.lowercased()

        if Self.isMediaFile(item) {
          mediaFiles.append(item)
        } else if Self.subtitleExtensions.contains(ext) {
          subtitleFiles.append(item)
        } else if ext == Self.pdfExtension {
          pdfFiles.append(item)
        }
      }
    }

    let expectedMediaRelativePaths = Set(mediaFiles.map { mediaURL in
      relativePath.isEmpty ? mediaURL.lastPathComponent : "\(relativePath)/\(mediaURL.lastPathComponent)"
    })
    try pruneMissingAudioFiles(in: folder, expectedRelativePaths: expectedMediaRelativePaths)

    let expectedSubfolderRelativePaths = Set(directories.map { dirURL in
      relativePath.isEmpty ? dirURL.lastPathComponent : "\(relativePath)/\(dirURL.lastPathComponent)"
    })
    try pruneMissingSubfolders(in: folder, expectedRelativePaths: expectedSubfolderRelativePaths)

    // Process media files (insert or update)
    if !mediaFiles.isEmpty {
      onProgressMessage?("Syncing media in \(url.lastPathComponent)...")
    }

    for mediaURL in mediaFiles {
      try await processAudioFile(
        at: mediaURL,
        folder: folder,
        relativePath: relativePath,
        subtitleFiles: subtitleFiles,
        pdfFiles: pdfFiles
      )
    }

    // Recursively process subdirectories
    for dirURL in directories {
      let subPath = relativePath.isEmpty
        ? dirURL.lastPathComponent
        : "\(relativePath)/\(dirURL.lastPathComponent)"
      _ = try await processDirectory(
        at: dirURL,
        relativePath: subPath,
        parent: folder,
        onProgressMessage: onProgressMessage
      )
    }

    return folder
  }

  private func findOrCreateFolder(at url: URL, relativePath: String) -> Folder {
    let name = url.lastPathComponent
    let folderId = Folder.generateDeterministicID(from: relativePath)

    let idDescriptor = FetchDescriptor<Folder>(
      predicate: #Predicate<Folder> { $0.id == folderId }
    )

    if let existing = try? modelContext.fetch(idDescriptor).first {
      if existing.relativePath != relativePath {
        existing.relativePath = relativePath
      }
      if existing.name != name {
        existing.name = name
      }
      return existing
    }

    let pathDescriptor = FetchDescriptor<Folder>(
      predicate: #Predicate<Folder> { $0.relativePath == relativePath }
    )

    if let existingByPath = try? modelContext.fetch(pathDescriptor).first {
      if existingByPath.name != name {
        existingByPath.name = name
      }
      return existingByPath
    }

    // Create a new record
    let folder = Folder(
      id: folderId,
      name: name,
      relativePath: relativePath,
      createdAt: getFileCreationDate(from: url)
    )
    modelContext.insert(folder)
    return folder
  }

  private func pruneMissingAudioFiles(in folder: Folder, expectedRelativePaths: Set<String>) throws {
    let folderID = folder.id
    let descriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { candidate in
        candidate.folder?.id == folderID
      }
    )

    let existingFiles = try modelContext.fetch(descriptor)
    for existing in existingFiles where !expectedRelativePaths.contains(existing.relativePath) {
      if let subtitleFile = existing.subtitleFile {
        modelContext.delete(subtitleFile)
      }
      modelContext.delete(existing)
    }
  }

  private func pruneMissingSubfolders(in folder: Folder, expectedRelativePaths: Set<String>) throws {
    let parentID = folder.id
    let descriptor = FetchDescriptor<Folder>(
      predicate: #Predicate<Folder> { candidate in
        candidate.parent?.id == parentID
      }
    )

    let existingSubfolders = try modelContext.fetch(descriptor)
    for existing in existingSubfolders where !expectedRelativePaths.contains(existing.relativePath) {
      try deleteFolderRecursively(existing)
    }
  }

  private func deleteFolderRecursively(_ folder: Folder) throws {
    let folderID = folder.id

    let fileDescriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { candidate in
        candidate.folder?.id == folderID
      }
    )
    let files = try modelContext.fetch(fileDescriptor)
    for file in files {
      if let subtitleFile = file.subtitleFile {
        modelContext.delete(subtitleFile)
      }
      modelContext.delete(file)
    }

    let subfolderDescriptor = FetchDescriptor<Folder>(
      predicate: #Predicate<Folder> { candidate in
        candidate.parent?.id == folderID
      }
    )
    let subfolders = try modelContext.fetch(subfolderDescriptor)
    for subfolder in subfolders {
      try deleteFolderRecursively(subfolder)
    }

    modelContext.delete(folder)
  }

  // MARK: - Audio File Handling

  private func processAudioFile(
    at url: URL,
    folder: Folder,
    relativePath: String,
    subtitleFiles: [URL],
    pdfFiles: [URL]
  ) async throws {
    let fileRelativePath = relativePath.isEmpty
      ? url.lastPathComponent
      : "\(relativePath)/\(url.lastPathComponent)"
    let deterministicID = ABFile.generateDeterministicID(from: fileRelativePath)
    
    let descriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate<ABFile> { $0.id == deterministicID }
    )

    let audioFile: ABFile
    
    if let existing = try? modelContext.fetch(descriptor).first {
      audioFile = existing
      if audioFile.folder?.id != folder.id {
        audioFile.folder = folder
        if !folder.audioFiles.contains(where: { $0.id == audioFile.id }) {
          folder.audioFiles.append(audioFile)
        }
      }
      audioFile.relativePath = fileRelativePath
    } else {
      audioFile = ABFile(
        id: deterministicID,
        displayName: url.lastPathComponent,
        fileType: ABFile.inferFileType(from: url),
        bookmarkData: Data(),
        createdAt: getFileCreationDate(from: url),
        folder: folder,
        relativePath: fileRelativePath
      )
      modelContext.insert(audioFile)
      folder.audioFiles.append(audioFile)
    }

    let baseName = url.deletingPathExtension().lastPathComponent

    // 1. Sync Subtitle File
    if let subtitleURL = findMatchingFile(baseName: baseName, in: subtitleFiles) {
      if audioFile.subtitleFile == nil {
        try await pairSubtitle(at: subtitleURL, with: audioFile)
      }
      // If needed we could update existing subtitle file content here
    } else {
      // If subtitle file no longer exists, remove relation
      if let existing = audioFile.subtitleFile {
        modelContext.delete(existing)
        audioFile.subtitleFile = nil
      }
    }

    // 2. Sync PDF File
    if findMatchingFile(baseName: baseName, in: pdfFiles) != nil {
      // Keep legacy bookmark field unused in managed-library mode.
      audioFile.pdfBookmarkData = nil
    } else {
      // If PDF no longer exists, clear bookmark
      audioFile.pdfBookmarkData = nil
    }

    // 3. Sync Transcription Record
    let audioFileIdString = audioFile.id.uuidString
    let transcriptionDescriptor = FetchDescriptor<Transcription>(
      predicate: #Predicate { $0.audioFileId == audioFileIdString }
    )

    let hasTranscriptionRecord = (try? modelContext.fetch(transcriptionDescriptor).first) != nil
    if audioFile.hasTranscriptionRecord != hasTranscriptionRecord {
      audioFile.hasTranscriptionRecord = hasTranscriptionRecord
    }

    // 4. Load and cache duration metadata (audio + video)
    audioFile.cachedDuration = await loadDuration(from: url)

    // Auto-save happens at end of batch usually, but we can save here if precise state needed immediately
    // modelContext.save() will be called by caller or auto-save
  }

  // MARK: - File Matching

  /// Finds a matching file
  private func findMatchingFile(baseName: String, in files: [URL]) -> URL? {
    return files.first { url in
      url.deletingPathExtension().lastPathComponent.lowercased() == baseName.lowercased()
    }
  }

  // MARK: - Pairing

  /// Associates a subtitle file
  private func pairSubtitle(at url: URL, with audioFile: ABFile) async throws {
    let subtitleFile = SubtitleFile(
      displayName: url.lastPathComponent,
      bookmarkData: Data(),
      audioFile: audioFile
    )

    modelContext.insert(subtitleFile)
    audioFile.subtitleFile = subtitleFile
  }

  // MARK: - Helpers

  /// Load duration metadata from audio/video file
  /// - Parameter url: File URL (must be accessible)
  /// - Returns: Duration in seconds, or nil if loading fails
  private func loadDuration(from url: URL) async -> Double? {
    let asset = AVURLAsset(url: url)
    
    do {
      let time = try await asset.load(.duration)
      let seconds = CMTimeGetSeconds(time)
      
      guard seconds.isFinite, seconds > 0 else {
        Logger.data.warning("[FolderImporter] Invalid duration for: \(url.lastPathComponent)")
        return nil
      }
      
      return seconds
    } catch {
      Logger.data.error("[FolderImporter] Failed to load duration for \(url.lastPathComponent): \(error.localizedDescription)")
      return nil
    }
  }

  private func getFileCreationDate(from url: URL) -> Date {
    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
    return attributes?[.creationDate] as? Date ?? Date()
  }

  private func copyItemToLibrary(from url: URL, destinationDirectory: URL) throws -> URL {
    let fileManager = FileManager.default

    var destinationURL = destinationDirectory.appendingPathComponent(url.lastPathComponent)
    if fileManager.fileExists(atPath: destinationURL.path) {
      destinationURL = .uniqueURL(for: destinationURL)
    }

    try fileManager.copyItem(at: url, to: destinationURL)
    return destinationURL
  }

  private func folderLibraryURL(for folder: Folder?) -> URL? {
    guard let folder else { return nil }
    let relativePath = folder.relativePath
    guard !relativePath.isEmpty else { return nil }
    return librarySettings.libraryDirectoryURL.appendingPathComponent(relativePath)
  }

  private static func isMediaFile(_ url: URL) -> Bool {
    if let contentType = try? url.resourceValues(forKeys: [.contentTypeKey]).contentType {
      if contentType.conforms(to: .audio) || contentType.conforms(to: .movie) {
        return true
      }
    }

    let ext = url.pathExtension.lowercased()
    guard !ext.isEmpty,
      let type = UTType(filenameExtension: ext)
    else {
      return false
    }

    return type.conforms(to: .audio) || type.conforms(to: .movie)
  }

}

// MARK: - Errors

enum ImportError: LocalizedError {
  case accessDenied

  var errorDescription: String? {
    switch self {
    case .accessDenied:
      return "Unable to access the selected folder"
    }
  }
}
