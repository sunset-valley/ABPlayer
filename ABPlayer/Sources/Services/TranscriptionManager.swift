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
    endpoint: String = "https://huggingface.co",
    progressCallback: (@Sendable (Double) -> Void)? = nil
  ) async throws {
    // If already downloading (and correct model), return
    if case .downloading(_, let currentName) = state, currentName == modelName {
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
            if case .downloading(_, let currentName) = self.state, currentName == modelName {
              self.state = .downloading(progress: progress, modelName: modelName)
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
    downloadBase: URL
  ) async throws {
    if engine.isModelLoaded(modelName) {
      return
    }

    state = .loading(modelName: modelName)
    do {
      try await engine.loadModel(modelName: modelName, downloadBase: downloadBase)
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
          downloadBase: settings.modelDirectoryURL
        )
      } catch is CancellationError {
        state = .cancelled
        throw CancellationError()
      } catch {
        // If the model files are already on disk the error is a load failure (e.g. WhisperKit
        // timing out on a network call under restricted networks such as China), not a missing
        // model.  Triggering a download would just time out again and show a misleading
        // "Download failed" message instead of the real load error.  Re-throw in that case.
        if settings.isModelDownloaded(modelName: settings.modelName) {
          throw error
        }
        // Model not present locally — download then retry.
        do {
          try await downloadModel(
            modelName: settings.modelName,
            downloadBase: settings.modelDirectoryURL,
            endpoint: settings.effectiveDownloadEndpoint
          )
        } catch is CancellationError {
          state = .cancelled
          throw CancellationError()
        }
        try await loadModel(
          modelName: settings.modelName,
          downloadBase: settings.modelDirectoryURL
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

      let cues: [SubtitleCue] = segments.compactMap { segment in
        let cleanedText = cleanTranscriptionText(segment.text)

        guard !cleanedText.isEmpty,
          segment.end > segment.start
        else {
          return nil
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
      wavURL.path
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

  /// Remove timestamp patterns like <|16.64|> from transcription text
  private func cleanTranscriptionText(_ text: String) -> String {
    // Pattern matches <|anything|> including timestamps like <|16.64|>
    let pattern = "<\\|[^>]*\\|>"
    guard let regex = try? NSRegularExpression(pattern: pattern, options: []) else {
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
    case .audioExtractionFailed(let reason):
      return "Audio extraction failed: \(reason)"
    }
  }
}
