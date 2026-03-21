import Foundation
import Observation

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
  private let engine: TranscriptionEngineProtocol
  private var downloadTask: Task<Void, Error>?
  var state: TranscriptionState = .idle
  /// Name of the most recently failed-to-load model (corrupt/incomplete files), nil if none
  var invalidModelName: String?

  init(engine: TranscriptionEngineProtocol = WhisperKitTranscriptionEngine()) {
    self.engine = engine
  }

  /// Download model with progress tracking
  func downloadModel(
    modelName: String,
    downloadBase: URL,
    endpoint: String,
    progressCallback: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    // If already downloading (and correct model), return
    if case let .downloading(_, currentName) = state, currentName == modelName {
      return
    }

    state = .downloading(progress: 0, modelName: modelName)

    let task = Task {
      try await engine.download(
        modelName: modelName,
        downloadBase: downloadBase,
        endpoint: endpoint,
        progressCallback: { @Sendable [weak self] progress in
          Task { @MainActor [weak self] in
            guard let self else { return }
            // Update state
            if case let .downloading(_, currentName) = self.state, currentName == modelName {
              self.state = .downloading(progress: progress.fractionCompleted, modelName: modelName)
            }
            // Process callback
            progressCallback?(progress)
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
      // URLSession throws URLError.cancelled instead of CancellationError
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
    if whisperKit != nil, loadedModelName == modelName {
      return
    }

    state = .loading(modelName: modelName)
    do {
      // Resolve the on-disk folder so WhisperKit skips the network file-listing call.
      // Without this, WhisperKit always contacts huggingface.co to list files even when
      // the model is already downloaded — which fails under restricted networks (e.g. China).
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
      invalidModelName = nil
      state = .idle
    } catch {
      if let engineError = error as? TranscriptionEngineError {
        switch engineError {
        case .modelsUnavailable:
          break
        case .modelNotLoaded, .underlying:
          invalidModelName = modelName
        }
      } else {
        invalidModelName = modelName
      }
      state = .failed("Failed to load model: \(error.localizedDescription)")
      throw error
    }
  }

  /// Returns the path to an already-downloaded model folder, or nil if not present.
  /// WhisperKit stores models at: <downloadBase>/models/argmaxinc/whisperkit-coreml/<variant>/
  ///
  /// Matching uses longest-known-ID-first to prevent overlap: a folder whose name
  /// contains both "large-v3" and "distil-large-v3" (e.g. distil-whisper_distil-large-v3)
  /// is attributed only to "distil-large-v3", never to "large-v3".
  private static func localModelFolder(modelName: String, downloadBase: URL) -> String? {
    let whisperKitDir = downloadBase
      .appendingPathComponent("models/argmaxinc/whisperkit-coreml")
    guard let contents = try? FileManager.default.contentsOfDirectory(
      at: whisperKitDir,
      includingPropertiesForKeys: [.isDirectoryKey],
      options: [.skipsHiddenFiles]
    ) else { return nil }

    // Sort known model IDs longest-first so the most specific name wins when
    // folder names overlap (e.g. "distil-large-v3" beats "large-v3").
    let knownModels = TranscriptionSettings.availableModels.map(\.id)
      .sorted { $0.count > $1.count }

    return contents.first { url in
      let folderName = url.lastPathComponent
      // Find the longest known model ID present in this folder name.
      guard let bestMatch = knownModels.first(where: { folderName.contains($0) }) else {
        return false
      }
      // Accept this folder only if its most-specific match is the requested model.
      return bestMatch == modelName
    }?.path
  }

  func checkIfModelExist(
    modelName: String = "distil-large-v3",
    downloadBase: URL,
    endpoint: String
  ) async throws -> Bool {
    if whisperKit != nil {
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
    audioURL: URL,
    settings: TranscriptionSettings
  ) async throws -> [SubtitleCue] {
    let fileName = audioURL.lastPathComponent

    if !engine.isModelLoaded(settings.modelName) {
      do {
        try await loadModel(
          modelName: settings.modelName,
          downloadBase: settings.modelDirectoryURL,
          endpoint: settings.effectiveDownloadEndpoint
        )
      } catch is CancellationError {
        state = .cancelled
        throw CancellationError()
      } catch {
        throw error
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
        let extractedURL = try await extractAudio(from: audioURL, settings: settings)
        extractedWavURL = extractedURL
        workingURL = extractedURL
      }

      let language = settings.language == "auto" ? nil : settings.language
      let audioPath = workingURL.path
      let segments = try await engine.transcribe(
        audioPath: audioPath,
        language: language
      )

      audioURL.stopAccessingSecurityScopedResource()

      if let wavURL = extractedWavURL {
        try? FileManager.default.removeItem(at: wavURL)
      }

      let cues: [SubtitleCue] = results.flatMap { result in
        result.segments.compactMap { segment in
          let cleanedText = cleanTranscriptionText(segment.text)

          guard !cleanedText.isEmpty,
                segment.end > segment.start
          else {
            return nil
          }

          return SubtitleCue(
            startTime: Double(segment.start),
            endTime: Double(segment.end),
            text: cleanedText
          )
        }

        return SubtitleCue(
          startTime: segment.start,
          endTime: segment.end,
          text: cleanedText
        )
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

  private func extractAudio(from videoURL: URL, settings: TranscriptionSettings) async throws -> URL {
    let fileName = videoURL.lastPathComponent
    state = .extractingAudio(progress: 0, fileName: fileName)

    let tempDir = FileManager.default.temporaryDirectory
    let wavFileName = videoURL.deletingPathExtension().lastPathComponent + "_extracted.wav"
    let wavURL = tempDir.appendingPathComponent(wavFileName)

    try? FileManager.default.removeItem(at: wavURL)

    guard let ffmpegPath = settings.effectiveFFmpegPath() else {
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

  // MARK: - Text Cleaning

  private static let timestampRegex = try? NSRegularExpression(pattern: "<\\|[^>]*\\|>")

  /// Remove timestamp patterns like <|16.64|> from transcription text
  private func cleanTranscriptionText(_ text: String) -> String {
    guard let regex = Self.timestampRegex else {
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
    case let .transcriptionFailed(reason):
      return "Transcription failed: \(reason)"
    }
  }
}
