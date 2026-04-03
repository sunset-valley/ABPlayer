import Foundation
import SwiftUI

/// User configurable transcription settings
@MainActor
@Observable
final class TranscriptionSettings {
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
  @AppStorage("transcription_model_directory") private var _modelDirectory: String = ""
  var modelDirectory: String {
    get { access(keyPath: \.modelDirectory); return _modelDirectory }
    set { withMutation(keyPath: \.modelDirectory) { _modelDirectory = newValue } }
  }

  /// Custom ffmpeg path (empty = auto-detect)
  @ObservationIgnored
  @AppStorage("transcription_ffmpeg_path") private var _ffmpegPath: String = ""
  var ffmpegPath: String {
    get { access(keyPath: \.ffmpegPath); return _ffmpegPath }
    set { withMutation(keyPath: \.ffmpegPath) { _ffmpegPath = newValue } }
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

  /// Default model directory in user home
  static var defaultModelDirectory: URL {
    let homeDir = FileManager.default.homeDirectoryForCurrentUser
    return homeDir.appendingPathComponent(".abplayer", isDirectory: true)
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
    Self.isModelDownloadedSync(modelName: modelName, baseDir: modelDirectoryURL)
  }

  /// Check if model is downloaded without blocking the main actor
  func isModelDownloadedAsync(modelName: String) async -> Bool {
    let baseDir = modelDirectoryURL
    return await Task.detached(priority: .utility) {
      Self.isModelDownloadedSync(modelName: modelName, baseDir: baseDir)
    }.value
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

      guard Self.detectedModelID(from: url.lastPathComponent) == modelName else {
        return false
      }

      return Self.hasRequiredModelFiles(at: url, fileManager: fileManager)
    }
  }


  /// Returns list of downloaded models asynchronously (non-blocking)
  func listDownloadedModelsAsync() async -> [(name: String, size: Int64)] {
    let url = modelDirectoryURL
    return await Task.detached(priority: .utility) {
      Self.listModelsSync(in: url)
    }.value
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
    let whisperKitDir =
      modelDirectoryURL
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent("argmaxinc", isDirectory: true)
      .appendingPathComponent("whisperkit-coreml", isDirectory: true)
    let modelDir = whisperKitDir.appendingPathComponent(name)
    try FileManager.default.removeItem(at: modelDir)
  }

  /// Move all models from old directory to new directory
  func migrateModels(from oldDir: URL, to newDir: URL) throws {
    let fileManager = FileManager.default

    // Create new directory if needed
    if !fileManager.fileExists(atPath: newDir.path) {
      try fileManager.createDirectory(at: newDir, withIntermediateDirectories: true)
    }

    guard fileManager.fileExists(atPath: oldDir.path) else { return }

    let contents = try fileManager.contentsOfDirectory(
      at: oldDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    )

    for url in contents {
      var isDir: ObjCBool = false
      guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir),
        isDir.boolValue
      else { continue }

      let destURL = newDir.appendingPathComponent(url.lastPathComponent)
      if !fileManager.fileExists(atPath: destURL.path) {
        try fileManager.moveItem(at: url, to: destURL)
      }
    }
  }

  /// Delete download cache for a model
  func deleteDownloadCache(modelName: String) {
    let fileManager = FileManager.default

    // WhisperKit downloads to models/argmaxinc/whisperkit-coreml/<model-name>
    // Model names are prefixed like "openai_whisper-tiny" or "distil-whisper_distil-large-v3"
    let whisperKitDir =
      modelDirectoryURL
      .appendingPathComponent("models", isDirectory: true)
      .appendingPathComponent("argmaxinc", isDirectory: true)
      .appendingPathComponent("whisperkit-coreml", isDirectory: true)

    guard fileManager.fileExists(atPath: whisperKitDir.path) else { return }

    do {
      let contents = try fileManager.contentsOfDirectory(
        at: whisperKitDir,
        includingPropertiesForKeys: [.isDirectoryKey],
        options: [.skipsHiddenFiles]
      )

      // Find and delete any folder containing the model name
      for url in contents {
        if url.lastPathComponent.contains(modelName) {
          try? fileManager.removeItem(at: url)
        }
      }

      // Also delete any temporary/incomplete download files
      let tempPatterns = [".tmp", ".download", ".partial"]
      for url in contents {
        let name = url.lastPathComponent
        if tempPatterns.contains(where: { name.contains($0) }) && name.contains(modelName) {
          try? fileManager.removeItem(at: url)
        }
      }
    } catch {
      // Ignore errors during cleanup
    }
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

  // MARK: - FFmpeg Path Management

  /// Get the effective ffmpeg path (custom → bundled → system)
  func effectiveFFmpegPath() -> String? {
    // 1. User override
    if !ffmpegPath.isEmpty, Self.isFFmpegValid(at: ffmpegPath) {
      return ffmpegPath
    }
    // 2. Bundled binary (primary — notarization-safe)
    if let bundledURL = Bundle.main.url(forAuxiliaryExecutable: "ffmpeg"),
       Self.isFFmpegValid(at: bundledURL.path) {
      return bundledURL.path
    }
    // 3. System install (Homebrew fallback)
    return Self.autoDetectFFmpegPath()
  }

  /// Check if ffmpeg is valid and executable at the given path
  static func isFFmpegValid(at path: String) -> Bool {
    let fileManager = FileManager.default
    var isDirectory: ObjCBool = false

    guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory),
      !isDirectory.boolValue
    else {
      return false
    }

    guard fileManager.isExecutableFile(atPath: path) else {
      return false
    }

    return true
  }

  /// Auto-detect ffmpeg installation path
  static func autoDetectFFmpegPath() -> String? {
    let possiblePaths = [
      "/opt/homebrew/bin/ffmpeg",
      "/usr/local/bin/ffmpeg",
      "/opt/local/bin/ffmpeg",
      "/sw/bin/ffmpeg",
    ]

    for path in possiblePaths {
      if isFFmpegValid(at: path) {
        return path
      }
    }

    return nil
  }
}
