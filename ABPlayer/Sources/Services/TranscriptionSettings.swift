import Foundation
import OSLog
import SwiftUI

/// User configurable transcription settings
@MainActor
@Observable
final class TranscriptionSettings {
  typealias BookmarkDataProducer = (URL) throws -> Data

  enum ModelMigrationResult {
    case migrated
    case skippedSourceMissing
    case skippedSourceInaccessible
    case skippedNoContents
    case failed(Error)
  }

  private var scopedModelDirectoryURL: URL?
  private var isModelDirectoryAccessActive = false

  @ObservationIgnored
  private let bookmarkDataProducer: BookmarkDataProducer

  /// Whether transcription feature is enabled
  @ObservationIgnored
  @AppStorage("transcription_enabled") private var _isEnabled: Bool = true
  var isEnabled: Bool {
    get { access(keyPath: \.isEnabled); return _isEnabled }
    set { withMutation(keyPath: \.isEnabled) { _isEnabled = newValue } }
  }

  /// WhisperKit model to use
  @ObservationIgnored
  @AppStorage("transcription_model") private var _modelName: String = "distil-large-v3"
  var modelName: String {
    get { access(keyPath: \.modelName); return _modelName }
    set { withMutation(keyPath: \.modelName) { _modelName = newValue } }
  }

  /// Language for transcription (auto = auto-detect)
  @ObservationIgnored
  @AppStorage("transcription_language") private var _language: String = "auto"
  var language: String {
    get { access(keyPath: \.language); return _language }
    set { withMutation(keyPath: \.language) { _language = newValue } }
  }

  /// Whether to automatically transcribe new audio files
  @ObservationIgnored
  @AppStorage("transcription_auto_transcribe") private var _autoTranscribe: Bool = false
  var autoTranscribe: Bool {
    get { access(keyPath: \.autoTranscribe); return _autoTranscribe }
    set { withMutation(keyPath: \.autoTranscribe) { _autoTranscribe = newValue } }
  }

  /// Whether to keep playback paused after dismissing word lookup
  @ObservationIgnored
  @AppStorage("transcription_pause_on_word_dismiss") private var _pauseOnWordDismiss: Bool = true
  var pauseOnWordDismiss: Bool {
    get { access(keyPath: \.pauseOnWordDismiss); return _pauseOnWordDismiss }
    set { withMutation(keyPath: \.pauseOnWordDismiss) { _pauseOnWordDismiss = newValue } }
  }

  /// Custom model download directory (empty = default location)
  @ObservationIgnored
  @AppStorage(UserDefaultsKey.transcriptionModelDirectory) private var _modelDirectory: String = ""
  var modelDirectory: String {
    get { access(keyPath: \.modelDirectory); return _modelDirectory }
    set { withMutation(keyPath: \.modelDirectory) { _modelDirectory = newValue } }
  }

  @ObservationIgnored
  @AppStorage(UserDefaultsKey.transcriptionModelDirectoryBookmark)
  private var _modelDirectoryBookmarkData: Data = Data()

  var modelDirectoryBookmarkData: Data? {
    get {
      let data = _modelDirectoryBookmarkData
      return data.isEmpty ? nil : data
    }
    set {
      _modelDirectoryBookmarkData = newValue ?? Data()
    }
  }

  /// Custom HuggingFace endpoint or mirror (empty = official HuggingFace)
  @ObservationIgnored
  @AppStorage("transcription_download_endpoint") private var _downloadEndpoint: String = ""
  var downloadEndpoint: String {
    get { access(keyPath: \.downloadEndpoint); return _downloadEndpoint }
    set { withMutation(keyPath: \.downloadEndpoint) { _downloadEndpoint = newValue } }
  }

  /// Last applied custom mirror endpoint
  @ObservationIgnored
  @AppStorage("transcription_last_custom_download_endpoint")
  private var _lastCustomDownloadEndpoint: String = ""
  var lastCustomDownloadEndpoint: String {
    get { access(keyPath: \.lastCustomDownloadEndpoint); return _lastCustomDownloadEndpoint }
    set { withMutation(keyPath: \.lastCustomDownloadEndpoint) { _lastCustomDownloadEndpoint = newValue } }
  }

  @ObservationIgnored
  @AppStorage(UserDefaultsKey.transcriptionLegacyDefaultModelDirectoryMigrated)
  private var _didMigrateLegacyDefaultModelDirectory = false

  init(performInitialMigration: Bool = true) {
    self.bookmarkDataProducer = TranscriptionSettings.defaultBookmarkData

    if performInitialMigration {
      migrateLegacyDefaultModelDirectoryIfNeeded()
    }

    beginModelDirectoryAccessSession()
  }

  init(
    performInitialMigration: Bool,
    bookmarkDataProducer: @escaping BookmarkDataProducer
  ) {
    self.bookmarkDataProducer = bookmarkDataProducer

    if performInitialMigration {
      migrateLegacyDefaultModelDirectoryIfNeeded()
    }

    beginModelDirectoryAccessSession()
  }

  // MARK: - Computed Properties

  /// Effective HuggingFace endpoint passed to WhisperKit downloads
  var effectiveDownloadEndpoint: String {
    let trimmed = downloadEndpoint.trimmingCharacters(in: .whitespaces)
    return trimmed.isEmpty ? "https://huggingface.co" : trimmed
  }

  /// Returns the model directory URL (user-specified or default)
  var modelDirectoryURL: URL {
    if modelDirectory.isEmpty {
      return TranscriptionSettings.defaultModelDirectory
    }
    return URL(fileURLWithPath: modelDirectory)
  }

  /// Default model directory in Application Support
  static var defaultModelDirectory: URL {
    let appSupportDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
      .first
      ?? FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library", isDirectory: true)
        .appendingPathComponent("Application Support", isDirectory: true)
    let folderName = Bundle.main.bundleIdentifier ?? "cc.ihugo.app.ABPlayer"
    return appSupportDir
      .appendingPathComponent(folderName, isDirectory: true)
      .appendingPathComponent("WhisperKit", isDirectory: true)
  }

  static var legacyDefaultModelDirectory: URL {
    FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".abplayer", isDirectory: true)
  }

  // MARK: - Available Options

  /// Available WhisperKit models (from smallest to largest)
  nonisolated static let availableModels: [(id: String, name: String)] = [
    ("tiny", "Tiny (~40MB, fastest)"),
    ("base", "Base (~80MB)"),
    ("small", "Small (~240MB)"),
    ("distil-large-v3", "Distil Large v3 (~700MB, recommended)"),
    ("large-v3", "Large v3 (~3GB, most accurate)"),
  ]

  /// Available languages for transcription
  static let availableLanguages: [(id: String, name: String)] = [
    ("auto", "Auto-detect"),
    ("en", "English"),
    ("zh", "Chinese"),
    ("ja", "Japanese"),
    ("ko", "Korean"),
    ("es", "Spanish"),
    ("fr", "French"),
    ("de", "German"),
  ]

  // MARK: - Model Management

  /// Check if a specific model is downloaded by verifying indicator files exist
  func isModelDownloaded(modelName: String) -> Bool {
    let baseDir = modelDirectoryURL
    do {
      return try withModelDirectoryAccessSync {
        Self.isModelDownloadedSync(modelName: modelName, baseDir: baseDir)
      }
    } catch {
      return false
    }
  }

  /// Check if model is downloaded without blocking the main actor
  func isModelDownloadedAsync(modelName: String) async -> Bool {
    let baseDir = modelDirectoryURL
    do {
      return try await withModelDirectoryAccess {
        await Task.detached(priority: .utility) {
          Self.isModelDownloadedSync(modelName: modelName, baseDir: baseDir)
        }.value
      }
    } catch {
      return false
    }
  }

  nonisolated private static func isModelDownloadedSync(modelName: String, baseDir: URL) -> Bool {
    let fileManager = FileManager.default
    let whisperKitDir = modelRootDirectory(in: baseDir)

    guard fileManager.fileExists(atPath: whisperKitDir.path) else { return false }

    guard
      let contents = try? fileManager.contentsOfDirectory(
        at: whisperKitDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )
    else { return false }

    return contents.contains { url in
      var isDir: ObjCBool = false
      guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
        isDir.boolValue
      else { return false }

      let folderName = url.lastPathComponent
      let matchedModelID = Self.detectedModelID(from: folderName)
      let matchesTarget = matchedModelID == modelName || folderName == modelName

      guard matchesTarget else { return false }

      return Self.hasRequiredModelFiles(at: url, fileManager: fileManager)
    }
  }


  /// Returns list of downloaded models asynchronously (non-blocking)
  func listDownloadedModelsAsync() async -> [(name: String, size: Int64)] {
    let url = modelDirectoryURL
    do {
      return try await withModelDirectoryAccess {
        await Task.detached(priority: .utility) {
          Self.listModelsSync(in: url)
        }.value
      }
    } catch {
      return []
    }
  }

  /// Synchronous helper for listing models (can run on background thread)
  nonisolated private static func listModelsSync(in baseDir: URL) -> [(name: String, size: Int64)] {
    let fileManager = FileManager.default

    // WhisperKit stores models in a nested structure
    let whisperKitDir = modelRootDirectory(in: baseDir)

    guard fileManager.fileExists(atPath: whisperKitDir.path) else { return [] }

    do {
      let contents = try fileManager.contentsOfDirectory(
        at: whisperKitDir,
        includingPropertiesForKeys: [.isDirectoryKey, .totalFileAllocatedSizeKey],
        options: [.skipsHiddenFiles]
      )

      return contents.compactMap { url -> (String, Int64)? in
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
          isDir.boolValue
        else { return nil }

        // Skip cache directories
        if url.lastPathComponent.hasPrefix(".") { return nil }

        // Check if it looks like a model directory (contains .mlmodelc or similar)
        let hasModelFiles = Self.hasAnyModelIndicatorFiles(at: url, fileManager: fileManager)

        guard hasModelFiles else { return nil }

        let size = Self.directorySize(at: url)
        return (url.lastPathComponent, size)
      }.sorted { $0.name < $1.name }
    } catch {
      return []
    }
  }

  /// Delete a specific model from disk
  func deleteModel(named name: String) throws {
    let baseDirectory = modelDirectoryURL
    try withModelDirectoryAccessSync {
      let whisperKitDir =
        baseDirectory
        .appendingPathComponent("models", isDirectory: true)
        .appendingPathComponent("argmaxinc", isDirectory: true)
        .appendingPathComponent("whisperkit-coreml", isDirectory: true)
      let modelDir = whisperKitDir.appendingPathComponent(name)
      try FileManager.default.removeItem(at: modelDir)
    }
  }

  /// Move all models from old directory to new directory
  func migrateModels(from oldDir: URL, to newDir: URL) throws {
    try withModelDirectoryAccessSync {
      let fileManager = FileManager.default

      guard fileManager.fileExists(atPath: oldDir.path) else { return }

      let sourceDirectories = try Self.directChildDirectories(in: oldDir, fileManager: fileManager)
      try Self.moveDirectories(sourceDirectories, to: newDir, fileManager: fileManager)
    }
  }

  func migrateModelsBestEffort(
    from oldDir: URL,
    oldDirectoryBookmarkData: Data?,
    to newDir: URL
  ) -> ModelMigrationResult {
    guard oldDir.standardizedFileURL.path != newDir.standardizedFileURL.path else {
      return .skippedNoContents
    }

    do {
      return try withPreviousModelDirectoryAccess(
        oldDir: oldDir,
        oldDirectoryBookmarkData: oldDirectoryBookmarkData
      ) { sourceDirectory in
        let fileManager = FileManager.default
        let sourceDirectories: [URL]

        do {
          sourceDirectories = try Self.directChildDirectories(in: sourceDirectory, fileManager: fileManager)
        } catch {
          if Self.isFileMissingError(error) {
            Logger.data.info("[TranscriptionSettings] Skip model migration because source is missing: \(sourceDirectory.path, privacy: .public)")
            return .skippedSourceMissing
          }
          if Self.isPermissionError(error) {
            Logger.data.info("[TranscriptionSettings] Skip model migration because source is inaccessible: \(sourceDirectory.path, privacy: .public)")
            return .skippedSourceInaccessible
          }
          return .failed(error)
        }

        guard !sourceDirectories.isEmpty else {
          return .skippedNoContents
        }

        do {
          try withModelDirectoryAccessSync {
            try Self.moveDirectories(sourceDirectories, to: newDir, fileManager: fileManager)
          }
          return .migrated
        } catch {
          Logger.data.error("[TranscriptionSettings] Failed to migrate models to new directory: \(error.localizedDescription, privacy: .public)")
          return .failed(error)
        }
      }
    } catch {
      if Self.isPermissionError(error) {
        Logger.data.info("[TranscriptionSettings] Skip model migration because source is inaccessible: \(oldDir.path, privacy: .public)")
        return .skippedSourceInaccessible
      }
      if Self.isFileMissingError(error) {
        Logger.data.info("[TranscriptionSettings] Skip model migration because source is missing: \(oldDir.path, privacy: .public)")
        return .skippedSourceMissing
      }
      Logger.data.error("[TranscriptionSettings] Failed during best-effort model migration: \(error.localizedDescription, privacy: .public)")
      return .failed(error)
    }
  }

  @discardableResult
  func performLegacyDefaultModelDirectoryMigration(from legacyDirectory: URL, to newDirectory: URL) -> Bool {
    guard modelDirectory.isEmpty else { return true }

    guard legacyDirectory.standardizedFileURL.path != newDirectory.standardizedFileURL.path else {
      return true
    }

    do {
      try migrateModels(from: legacyDirectory, to: newDirectory)
      return true
    } catch {
      Logger.data.error("[TranscriptionSettings] Failed to migrate legacy model directory: \(error.localizedDescription, privacy: .public)")
      return false
    }
  }

  func migrateLegacyDefaultModelDirectoryIfNeeded() {
    guard !_didMigrateLegacyDefaultModelDirectory else { return }

    if performLegacyDefaultModelDirectoryMigration(
      from: Self.legacyDefaultModelDirectory,
      to: Self.defaultModelDirectory
    ) {
      _didMigrateLegacyDefaultModelDirectory = true
    }
  }

  /// Delete download cache for a model
  func deleteDownloadCache(modelName: String) {
    let baseDirectory = modelDirectoryURL
    do {
      try withModelDirectoryAccessSync {
        let fileManager = FileManager.default

        let whisperKitDir =
          baseDirectory
          .appendingPathComponent("models", isDirectory: true)
          .appendingPathComponent("argmaxinc", isDirectory: true)
          .appendingPathComponent("whisperkit-coreml", isDirectory: true)

        guard fileManager.fileExists(atPath: whisperKitDir.path) else { return }

        let contents = try fileManager.contentsOfDirectory(
          at: whisperKitDir,
          includingPropertiesForKeys: [.isDirectoryKey],
          options: [.skipsHiddenFiles]
        )

        for url in contents where url.lastPathComponent.contains(modelName) {
          try? fileManager.removeItem(at: url)
        }

        let tempPatterns = [".tmp", ".download", ".partial"]
        for url in contents {
          let name = url.lastPathComponent
          if tempPatterns.contains(where: { name.contains($0) }) && name.contains(modelName) {
            try? fileManager.removeItem(at: url)
          }
        }
      }
    } catch {
      // Ignore errors during cleanup.
    }
  }

  func setModelDirectory(_ url: URL) throws {
    let didStartAccessing = url.startAccessingSecurityScopedResource()
    defer {
      if didStartAccessing {
        url.stopAccessingSecurityScopedResource()
      }
    }

    let bookmarkData = try bookmarkDataProducer(url)
    modelDirectory = url.path
    modelDirectoryBookmarkData = bookmarkData
    beginModelDirectoryAccessSession()
  }

  func beginModelDirectoryAccessSession() {
    guard !modelDirectory.isEmpty else {
      endModelDirectoryAccessSession()
      return
    }

    if isModelDirectoryAccessActive,
      let scopedModelDirectoryURL,
      scopedModelDirectoryURL.standardizedFileURL.path == modelDirectoryURL.standardizedFileURL.path
    {
      return
    }

    endModelDirectoryAccessSession()

    do {
      if let scopedURL = try resolveScopedModelDirectoryURL(),
        scopedURL.startAccessingSecurityScopedResource()
      {
        scopedModelDirectoryURL = scopedURL
        isModelDirectoryAccessActive = true
      }
    } catch {
      scopedModelDirectoryURL = nil
      isModelDirectoryAccessActive = false
    }
  }

  func endModelDirectoryAccessSession() {
    if let scopedModelDirectoryURL, isModelDirectoryAccessActive {
      scopedModelDirectoryURL.stopAccessingSecurityScopedResource()
    }
    scopedModelDirectoryURL = nil
    isModelDirectoryAccessActive = false
  }

  func withModelDirectoryAccess<T>(_ operation: () async throws -> T) async throws -> T {
    alignModelDirectoryAccessSessionWithCurrentPath()

    if isModelDirectoryAccessActive {
      return try await operation()
    }

    guard !modelDirectory.isEmpty else {
      return try await operation()
    }

    do {
      if let scopedURL = try resolveScopedModelDirectoryURL(),
        scopedURL.startAccessingSecurityScopedResource()
      {
        defer {
          scopedURL.stopAccessingSecurityScopedResource()
        }
        return try await operation()
      }
    } catch {
      return try await operation()
    }

    return try await operation()
  }

  func withModelDirectoryAccessSync<T>(_ operation: () throws -> T) throws -> T {
    alignModelDirectoryAccessSessionWithCurrentPath()

    if isModelDirectoryAccessActive {
      return try operation()
    }

    guard !modelDirectory.isEmpty else {
      return try operation()
    }

    do {
      if let scopedURL = try resolveScopedModelDirectoryURL(),
        scopedURL.startAccessingSecurityScopedResource()
      {
        defer {
          scopedURL.stopAccessingSecurityScopedResource()
        }
        return try operation()
      }
    } catch {
      return try operation()
    }

    return try operation()
  }

  /// Calculate total size of a directory
  nonisolated private static func directorySize(at url: URL) -> Int64 {
    let fileManager = FileManager.default
    var totalSize: Int64 = 0

    guard
      let enumerator = fileManager.enumerator(
        at: url,
        includingPropertiesForKeys: [.fileSizeKey],
        options: [.skipsHiddenFiles]
      )
    else { return 0 }

    for case let fileURL as URL in enumerator {
      if let fileSize = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
        totalSize += Int64(fileSize)
      }
    }

    return totalSize
  }

  nonisolated private static func modelRootDirectory(in baseDir: URL) -> URL {
    baseDir
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent("argmaxinc", isDirectory: true)
      .appendingPathComponent("whisperkit-coreml", isDirectory: true)
  }

  nonisolated private static func hasRequiredModelFiles(at url: URL, fileManager: FileManager) -> Bool {
    ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "config.json"].allSatisfy { indicator in
      fileManager.fileExists(atPath: url.appendingPathComponent(indicator).path)
    }
  }

  nonisolated private static func hasAnyModelIndicatorFiles(at url: URL, fileManager: FileManager) -> Bool {
    ["AudioEncoder.mlmodelc", "TextDecoder.mlmodelc", "config.json"].contains { indicator in
      fileManager.fileExists(atPath: url.appendingPathComponent(indicator).path)
    }
  }

  private func withPreviousModelDirectoryAccess<T>(
    oldDir: URL,
    oldDirectoryBookmarkData: Data?,
    operation: (URL) throws -> T
  ) throws -> T {
    let sourceDirectory = oldDir.standardizedFileURL
    let isDefaultDirectory =
      sourceDirectory.path == Self.defaultModelDirectory.standardizedFileURL.path

    if isDefaultDirectory {
      return try operation(sourceDirectory)
    }

    if let oldDirectoryBookmarkData {
      do {
        var isStale = false
        let scopedURL = try URL(
          resolvingBookmarkData: oldDirectoryBookmarkData,
          options: [.withSecurityScope],
          relativeTo: nil,
          bookmarkDataIsStale: &isStale
        )
        let didStartAccessing = scopedURL.startAccessingSecurityScopedResource()
        defer {
          if didStartAccessing {
            scopedURL.stopAccessingSecurityScopedResource()
          }
        }
        return try operation(scopedURL)
      } catch {
        Logger.data.info("[TranscriptionSettings] Failed to restore previous model directory bookmark: \(error.localizedDescription, privacy: .public)")
        return try operation(sourceDirectory)
      }
    }

    return try operation(sourceDirectory)
  }

  nonisolated private static func directChildDirectories(
    in directory: URL,
    fileManager: FileManager
  ) throws -> [URL] {
    let contents = try fileManager.contentsOfDirectory(
      at: directory,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    return contents.filter { url in
      var isDir: ObjCBool = false
      return fileManager.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }
  }

  nonisolated private static func moveDirectories(
    _ sourceDirectories: [URL],
    to destinationRoot: URL,
    fileManager: FileManager
  ) throws {
    if !fileManager.fileExists(atPath: destinationRoot.path) {
      try fileManager.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
    }

    for url in sourceDirectories {
      let destination = destinationRoot.appendingPathComponent(url.lastPathComponent)
      if !fileManager.fileExists(atPath: destination.path) {
        try fileManager.moveItem(at: url, to: destination)
      }
    }
  }

  nonisolated private static func isPermissionError(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
      if nsError.code == NSFileReadNoPermissionError || nsError.code == NSFileWriteNoPermissionError {
        return true
      }
    }
    if nsError.domain == NSPOSIXErrorDomain {
      if nsError.code == EACCES || nsError.code == EPERM {
        return true
      }
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
      return isPermissionError(underlying)
    }
    return false
  }

  nonisolated private static func isFileMissingError(_ error: Error) -> Bool {
    let nsError = error as NSError
    if nsError.domain == NSCocoaErrorDomain {
      if nsError.code == NSFileReadNoSuchFileError || nsError.code == NSFileNoSuchFileError {
        return true
      }
    }
    if nsError.domain == NSPOSIXErrorDomain {
      if nsError.code == ENOENT {
        return true
      }
    }
    if let underlying = nsError.userInfo[NSUnderlyingErrorKey] as? NSError {
      return isFileMissingError(underlying)
    }
    return false
  }

  private func resolveScopedModelDirectoryURL() throws -> URL? {
    if let bookmarkData = modelDirectoryBookmarkData {
      var isStale = false
      let scopedURL = try URL(
        resolvingBookmarkData: bookmarkData,
        options: [.withSecurityScope],
        relativeTo: nil,
        bookmarkDataIsStale: &isStale
      )

      if isStale {
        modelDirectoryBookmarkData = try bookmarkDataProducer(scopedURL)
      }

      return scopedURL
    }

    let url = modelDirectoryURL
    if let newBookmark = try? bookmarkDataProducer(url) {
      modelDirectoryBookmarkData = newBookmark
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

  private func alignModelDirectoryAccessSessionWithCurrentPath() {
    guard isModelDirectoryAccessActive, let scopedModelDirectoryURL else {
      return
    }

    let activePath = scopedModelDirectoryURL.standardizedFileURL.path
    let targetPath = modelDirectoryURL.standardizedFileURL.path
    if activePath != targetPath {
      endModelDirectoryAccessSession()
      beginModelDirectoryAccessSession()
    }
  }

  nonisolated private static func defaultBookmarkData(for url: URL) throws -> Data {
    try url.bookmarkData(
      options: [.withSecurityScope],
      includingResourceValuesForKeys: nil,
      relativeTo: nil
    )
  }

  nonisolated private static func detectedModelID(from folderName: String) -> String? {
    let knownModels = availableModels.map(\.id).sorted { $0.count > $1.count }
    return knownModels.first { folderName.contains($0) }
  }

  /// Format byte size for display
  static func formatSize(_ bytes: Int64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: bytes)
  }
}
