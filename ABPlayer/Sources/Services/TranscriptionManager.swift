import Foundation
import Observation
@preconcurrency import WhisperKit

/// Transcription progress and state
enum TranscriptionState: Equatable {
  case unavailable
  case idle
  case downloading(progress: Double, modelName: String)
  case loading(modelName: String)
  case extractingAudio(progress: Double, fileName: String)
  case transcribing(progress: Double, fileName: String)
  case completed
  case failed(String)
  case cancelled
}

/// Manages audio transcription using WhisperKit
@MainActor
@Observable
final class TranscriptionManager {
  private let runtime = TranscriptionRuntime()
  private var loadedModelName: String?
  private var downloadTask: Task<Void, Error>?
  var state: TranscriptionState = .idle
  /// Name of the most recently failed-to-load model (corrupt/incomplete files), nil if none
  var invalidModelName: String?

  /// Whether the model is loaded and ready
  var isModelLoaded: Bool {
    loadedModelName != nil
  }

  /// Download model with progress tracking
  func downloadModel(
    modelName: String,
    downloadBase: URL,
    endpoint: String,
    progressCallback: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    if case let .downloading(_, currentName) = state, currentName == modelName {
      return
    }

    state = .downloading(progress: 0, modelName: modelName)

    let task = Task {
      _ = try await WhisperKit.download(
        variant: modelName,
        downloadBase: downloadBase,
        endpoint: endpoint,
        progressCallback: { @Sendable [weak self] progress in
          Task { @MainActor [weak self] in
            guard let self else { return }
            let fractionCompleted = progress.fractionCompleted
            if case let .downloading(_, currentName) = self.state, currentName == modelName {
              self.state = .downloading(progress: fractionCompleted, modelName: modelName)
            }
            progressCallback?(fractionCompleted)
          }
        }
      )
    }

    downloadTask = task

    do {
      try await task.value
      downloadTask = nil

      if case .cancelled = state {
        throw CancellationError()
      }
      state = .idle
    } catch is CancellationError {
      downloadTask = nil
      state = .cancelled
      throw CancellationError()
    } catch let urlError as URLError where urlError.code == .cancelled {
      downloadTask = nil
      state = .cancelled
      throw CancellationError()
    } catch {
      downloadTask = nil
      state = .failed("Failed to download model: \(error.localizedDescription)")
      throw error
    }
  }

  /// Cancel current download
  func cancelDownload() {
    downloadTask?.cancel()
    state = .cancelled
  }

  /// Initialize WhisperKit with the specified model and download folder
  func loadModel(
    modelName: String = "distil-large-v3",
    downloadBase: URL,
    endpoint: String
  ) async throws {
    if await runtime.hasLoadedModel(named: modelName) {
      loadedModelName = modelName
      return
    }

    state = .loading(modelName: modelName)
    do {
      try await runtime.loadModel(
        modelName: modelName,
        downloadBase: downloadBase,
        endpoint: endpoint
      )
      loadedModelName = modelName
      invalidModelName = nil
      state = .idle
    } catch let whisperError as WhisperError {
      if case .modelsUnavailable = whisperError {
        invalidModelName = nil
      } else {
        invalidModelName = modelName
      }
      state = .failed("Failed to load model: \(whisperError.localizedDescription)")
      throw whisperError
    } catch {
      invalidModelName = modelName
      state = .failed("Failed to load model: \(error.localizedDescription)")
      throw error
    }
  }

  func checkIfModelExist(
    modelName: String = "distil-large-v3",
    downloadBase: URL,
    endpoint: String
  ) async throws -> Bool {
    if await runtime.hasLoadedModel(named: modelName) {
      loadedModelName = modelName
      return true
    }
    do {
      try await loadModel(
        modelName: modelName,
        downloadBase: downloadBase,
        endpoint: endpoint
      )
    } catch WhisperError.modelsUnavailable {
      return false
    } catch {
      throw error
    }
    return true
  }

  /// Transcribe audio file using settings
  func transcribe(
    audioFileID: UUID,
    audioURL: URL,
    settings: TranscriptionSettings
  ) async throws -> [SubtitleCue] {
    let fileName = audioURL.lastPathComponent
    let runtimeConfig = RuntimeConfig(settings: settings)

    if !(await runtime.hasLoadedModel(named: runtimeConfig.modelName)) {
      do {
        try await loadModel(
          modelName: runtimeConfig.modelName,
          downloadBase: runtimeConfig.downloadBase,
          endpoint: runtimeConfig.endpoint
        )
      } catch is CancellationError {
        state = .cancelled
        throw CancellationError()
      } catch {
        if await settings.isModelDownloadedAsync(modelName: runtimeConfig.modelName) {
          throw error
        }
        do {
          try await downloadModel(
            modelName: runtimeConfig.modelName,
            downloadBase: runtimeConfig.downloadBase,
            endpoint: runtimeConfig.endpoint
          )
        } catch is CancellationError {
          state = .cancelled
          throw CancellationError()
        }
        try await loadModel(
          modelName: runtimeConfig.modelName,
          downloadBase: runtimeConfig.downloadBase,
          endpoint: runtimeConfig.endpoint
        )
      }
    }

    state = .transcribing(progress: 0, fileName: fileName)

    var extractedWavURL: URL?
    var workingURL = audioURL

    do {
      guard audioURL.startAccessingSecurityScopedResource() else {
        throw TranscriptionError.accessDenied
      }

      if isVideoFile(audioURL) {
        let extractedURL = try await extractAudio(from: audioURL, ffmpegPath: runtimeConfig.ffmpegPath)
        extractedWavURL = extractedURL
        workingURL = extractedURL
      }

      let cues = try await runtime.transcribe(
        audioPath: workingURL.path,
        language: runtimeConfig.language,
        audioFileID: audioFileID
      )

      audioURL.stopAccessingSecurityScopedResource()

      if let wavURL = extractedWavURL {
        try? FileManager.default.removeItem(at: wavURL)
      }

      state = .completed
      return cues
    } catch is CancellationError {
      audioURL.stopAccessingSecurityScopedResource()
      if let wavURL = extractedWavURL {
        try? FileManager.default.removeItem(at: wavURL)
      }
      throw CancellationError()
    } catch {
      audioURL.stopAccessingSecurityScopedResource()
      if let wavURL = extractedWavURL {
        try? FileManager.default.removeItem(at: wavURL)
      }
      state = .failed(error.localizedDescription)
      throw error
    }
  }

  /// Reset state to idle
  func reset() {
    state = .idle
  }

  // MARK: - Audio Extraction

  private func extractAudio(from videoURL: URL, ffmpegPath: String?) async throws -> URL {
    let fileName = videoURL.lastPathComponent
    state = .extractingAudio(progress: 0, fileName: fileName)

    let tempDir = FileManager.default.temporaryDirectory
    let wavFileName = videoURL.deletingPathExtension().lastPathComponent + "_extracted.wav"
    let wavURL = tempDir.appendingPathComponent(wavFileName)

    try? FileManager.default.removeItem(at: wavURL)

    guard let ffmpegPath else {
      throw TranscriptionError.audioExtractionFailed(
        "FFmpeg not found. Please install FFmpeg or configure the path in Settings."
      )
    }

    let process = Process()
    process.executableURL = URL(fileURLWithPath: ffmpegPath)
    process.arguments = [
      "-i", videoURL.path,
      "-vn",
      "-ar", "16000",
      "-ac", "1",
      "-c:a", "pcm_s16le",
      "-y",
      wavURL.path,
    ]

    let errorPipe = Pipe()
    process.standardError = errorPipe
    process.standardOutput = Pipe()

    return try await withCheckedThrowingContinuation { continuation in
      Task.detached {
        do {
          try process.run()
          process.waitUntilExit()

          let exitCode = process.terminationStatus
          if exitCode == 0 {
            await MainActor.run {
              self.state = .extractingAudio(progress: 1.0, fileName: fileName)
            }
            continuation.resume(returning: wavURL)
          } else {
            let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
            continuation.resume(
              throwing: TranscriptionError.audioExtractionFailed(
                "ffmpeg failed with code \(exitCode): \(errorMessage)"
              )
            )
          }
        } catch {
          continuation.resume(throwing: error)
        }
      }
    }
  }

  private func isVideoFile(_ url: URL) -> Bool {
    let videoExtensions: Set<String> = ["mp4", "mov", "m4v", "avi", "mkv", "webm"]
    return videoExtensions.contains(url.pathExtension.lowercased())
  }

}

private extension TranscriptionManager {
  struct RuntimeConfig: Sendable {
    let modelName: String
    let downloadBase: URL
    let endpoint: String
    let language: String?
    let ffmpegPath: String?

    @MainActor
    init(settings: TranscriptionSettings) {
      modelName = settings.modelName
      downloadBase = settings.modelDirectoryURL
      endpoint = settings.effectiveDownloadEndpoint
      language = settings.language == "auto" ? nil : settings.language
      ffmpegPath = settings.effectiveFFmpegPath()
    }
  }
}

private actor TranscriptionRuntime {
  private var whisperKit: WhisperKit?
  private var loadedModelName: String?

  func hasLoadedModel(named modelName: String) -> Bool {
    whisperKit != nil && loadedModelName == modelName
  }

  func loadModel(
    modelName: String,
    downloadBase: URL,
    endpoint: String
  ) async throws {
    if whisperKit != nil, loadedModelName == modelName {
      return
    }

    let localFolder = Self.localModelFolder(modelName: modelName, downloadBase: downloadBase)
    let config = WhisperKitConfig(
      model: modelName,
      downloadBase: downloadBase,
      modelEndpoint: endpoint,
      modelFolder: localFolder,
      download: false
    )

    whisperKit = try await WhisperKit(config)
    loadedModelName = modelName
  }

  func transcribe(
    audioPath: String,
    language: String?,
    audioFileID: UUID
  ) async throws -> [SubtitleCue] {
    guard let whisperKit else {
      throw TranscriptionError.modelNotLoaded
    }

    let options = DecodingOptions(language: language)
    let results = try await whisperKit.transcribe(
      audioPath: audioPath,
      decodeOptions: options
    )

    var cueIndex = 0
    return results.flatMap { result in
      result.segments.compactMap { segment in
        let cleanedText = Self.cleanTranscriptionText(segment.text)

        guard !cleanedText.isEmpty,
          segment.end > segment.start
        else {
          return nil
        }

        defer { cueIndex += 1 }
        let startTime = Double(segment.start)
        let endTime = Double(segment.end)
        let cueID = SubtitleCue.generateDeterministicID(
          audioFileID: audioFileID,
          cueIndex: cueIndex,
          startTime: startTime,
          endTime: endTime
        )

        return SubtitleCue(
          id: cueID,
          startTime: startTime,
          endTime: endTime,
          text: cleanedText
        )
      }
    }
  }

  private static let timestampRegex = try? NSRegularExpression(pattern: "<\\|[^>]*\\|>")

  private static func cleanTranscriptionText(_ text: String) -> String {
    guard let regex = timestampRegex else {
      return text.trimmingCharacters(in: .whitespaces)
    }

    let range = NSRange(text.startIndex..., in: text)
    let cleaned = regex.stringByReplacingMatches(
      in: text,
      options: [],
      range: range,
      withTemplate: ""
    )

    return cleaned.trimmingCharacters(in: .whitespaces)
  }

  private static func localModelFolder(modelName: String, downloadBase: URL) -> String? {
    let whisperKitDir = downloadBase
      .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
    guard let contents = try? FileManager.default.contentsOfDirectory(
      at: whisperKitDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return nil }

    let knownModels = TranscriptionSettings.availableModels.map(\.id)
      .sorted { $0.count > $1.count }

    return contents.first { url in
      let folderName = url.lastPathComponent
      guard let bestMatch = knownModels.first(where: { folderName.contains($0) }) else {
        return false
      }
      return bestMatch == modelName
    }?.path
  }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
  case modelNotLoaded
  case accessDenied
  case audioExtractionFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelNotLoaded:
      return "WhisperKit model is not loaded"
    case .accessDenied:
      return "Cannot access the audio file"
    case let .audioExtractionFailed(reason):
      return "Audio extraction failed: \(reason)"
    }
  }
}
