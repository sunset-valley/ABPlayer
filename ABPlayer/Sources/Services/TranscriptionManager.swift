import AVFoundation
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
  private var audioExtractionTask: Task<URL, Error>?
  private var transcriptionTask: Task<[SubtitleCue], Error>?
  private var lastPublishedTranscriptionProgressPercent: Int?
  private var cancellationRequested = false
  private var stateObservers: [UUID: @MainActor (TranscriptionState) -> Void] = [:]
  var state: TranscriptionState = .idle {
    didSet {
      notifyStateObservers()
    }
  }
  /// Name of the most recently failed-to-load model (corrupt/incomplete files), nil if none
  var invalidModelName: String?

  @discardableResult
  func addStateObserver(_ observer: @escaping @MainActor (TranscriptionState) -> Void) -> UUID {
    let observerID = UUID()
    stateObservers[observerID] = observer
    observer(state)
    return observerID
  }

  func removeStateObserver(_ observerID: UUID) {
    stateObservers.removeValue(forKey: observerID)
  }

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

  func cancelTranscription() {
    cancellationRequested = true
    transcriptionTask?.cancel()
    transcriptionTask = nil
    audioExtractionTask?.cancel()
    audioExtractionTask = nil
    lastPublishedTranscriptionProgressPercent = nil
    state = .cancelled
  }

  /// Initialize WhisperKit with the specified model and download folder
  func loadModel(
    modelName: String = "distil-large-v3",
    downloadBase: URL,
    endpoint: String
  ) async throws {
    if await runtime.hasLoadedModel(named: modelName, downloadBase: downloadBase) {
      loadedModelName = modelName
      invalidModelName = nil
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
    if await runtime.hasLoadedModel(named: modelName, downloadBase: downloadBase) {
      loadedModelName = modelName
      invalidModelName = nil
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
    cancellationRequested = false
    defer { cancellationRequested = false }

    let fileName = audioURL.lastPathComponent
    let runtimeConfig = RuntimeConfig(settings: settings)

    try throwIfCancellationRequested()

    if !(await runtime.hasLoadedModel(named: runtimeConfig.modelName, downloadBase: runtimeConfig.downloadBase)) {
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

    try throwIfCancellationRequested()

    lastPublishedTranscriptionProgressPercent = 0

    var extractedWavURL: URL?
    var workingURL = audioURL

    do {
      try throwIfCancellationRequested()

      if try await shouldExtractAudio(from: audioURL) {
        try throwIfCancellationRequested()
        let extractedURL = try await extractAudio(from: audioURL)
        extractedWavURL = extractedURL
        workingURL = extractedURL
      }

      try throwIfCancellationRequested()
      state = .transcribing(progress: 0, fileName: fileName)

      let transcribeTask = Task { [runtime] in
        try Task.checkCancellation()
        return try await runtime.transcribe(
          audioPath: workingURL.path,
          language: runtimeConfig.language,
          audioFileID: audioFileID,
          onProgress: { [weak self] progress in
            Task { @MainActor [weak self] in
              self?.publishTranscribingProgressIfNeeded(progress, fileName: fileName)
            }
          }
        )
      }
      transcriptionTask = transcribeTask
      defer { transcriptionTask = nil }

      let cues = try await withTaskCancellationHandler {
        try await transcribeTask.value
      } onCancel: {
        transcribeTask.cancel()
      }

      if let wavURL = extractedWavURL {
        try? FileManager.default.removeItem(at: wavURL)
      }

      lastPublishedTranscriptionProgressPercent = nil
      state = .completed
      return cues
    } catch is CancellationError {
      if let wavURL = extractedWavURL {
        try? FileManager.default.removeItem(at: wavURL)
      }
      lastPublishedTranscriptionProgressPercent = nil
      state = .cancelled
      throw CancellationError()
    } catch {
      if let wavURL = extractedWavURL {
        try? FileManager.default.removeItem(at: wavURL)
      }
      lastPublishedTranscriptionProgressPercent = nil
      state = .failed(error.localizedDescription)
      throw error
    }
  }

  /// Reset state to idle
  func reset() {
    cancellationRequested = false
    downloadTask?.cancel()
    downloadTask = nil
    transcriptionTask?.cancel()
    transcriptionTask = nil
    audioExtractionTask?.cancel()
    audioExtractionTask = nil
    lastPublishedTranscriptionProgressPercent = nil
    state = .idle
  }

  /// Invalidate runtime cache so next load uses latest model/directory settings
  func invalidateLoadedModel() {
    loadedModelName = nil
    invalidModelName = nil
    Task {
      await runtime.invalidateLoadedModel()
    }
  }

  // MARK: - Audio Extraction

  private func extractAudio(from mediaURL: URL) async throws -> URL {
    let fileName = mediaURL.lastPathComponent
    state = .extractingAudio(progress: 0, fileName: fileName)

    let tempDir = FileManager.default.temporaryDirectory
    let wavFileName = mediaURL.deletingPathExtension().lastPathComponent + "_extracted.wav"
    let wavURL = tempDir.appendingPathComponent(wavFileName)

    try? FileManager.default.removeItem(at: wavURL)

    let extractionTask = Task.detached(priority: .background) {
      try Task.checkCancellation()

      let asset = AVURLAsset(url: mediaURL)
      let audioTracks = try await asset.loadTracks(withMediaType: .audio)
      guard let audioTrack = audioTracks.first else {
        throw TranscriptionError.audioExtractionFailed("No audio track found in media file")
      }

      let outputSettings: [String: Any] = [
        AVFormatIDKey: kAudioFormatLinearPCM,
        AVSampleRateKey: 16000,
        AVNumberOfChannelsKey: 1,
        AVLinearPCMBitDepthKey: 16,
        AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsFloatKey: false,
        AVLinearPCMIsNonInterleaved: false,
      ]

      let reader = try AVAssetReader(asset: asset)
      let trackOutput = AVAssetReaderTrackOutput(track: audioTrack, outputSettings: outputSettings)
      trackOutput.alwaysCopiesSampleData = false

      guard reader.canAdd(trackOutput) else {
        throw TranscriptionError.audioExtractionFailed("Cannot read audio track")
      }
      reader.add(trackOutput)

      guard reader.startReading() else {
        let reason = reader.error?.localizedDescription ?? "Unknown reader error"
        throw TranscriptionError.audioExtractionFailed("Failed to start reading audio: \(reason)")
      }

      do {
        var outputFile: AVAudioFile?
        var wroteSamples = false
        var processedBufferCount = 0
        var pendingBuffers: [AVAudioPCMBuffer] = []
        pendingBuffers.reserveCapacity(8)

        func flushPendingBuffers() throws {
          for buffer in pendingBuffers {
            if outputFile == nil {
              outputFile = try AVAudioFile(
                forWriting: wavURL,
                settings: buffer.format.settings,
                commonFormat: buffer.format.commonFormat,
                interleaved: buffer.format.isInterleaved
              )
            }

            if buffer.frameLength > 0 {
              try outputFile?.write(from: buffer)
              wroteSamples = true
            }
          }
          pendingBuffers.removeAll(keepingCapacity: true)
        }

        while let sampleBuffer = trackOutput.copyNextSampleBuffer() {
          try Task.checkCancellation()
          processedBufferCount += 1

          guard let pcmBuffer = Self.makePCMBuffer(from: sampleBuffer) else {
            continue
          }

          pendingBuffers.append(pcmBuffer)

          if pendingBuffers.count >= 8 {
            try flushPendingBuffers()
            await Task.yield()
          } else if processedBufferCount.isMultiple(of: 16) {
            await Task.yield()
          }
        }

        if !pendingBuffers.isEmpty {
          try flushPendingBuffers()
        }

        if reader.status == .failed {
          let reason = reader.error?.localizedDescription ?? "Unknown reader failure"
          throw TranscriptionError.audioExtractionFailed("Audio reading failed: \(reason)")
        }

        guard wroteSamples else {
          throw TranscriptionError.audioExtractionFailed("No audio samples were extracted")
        }

        return wavURL
      } catch is CancellationError {
        reader.cancelReading()
        throw CancellationError()
      }
    }

    audioExtractionTask = extractionTask
    defer { audioExtractionTask = nil }

    let extractedURL = try await withTaskCancellationHandler {
      try await extractionTask.value
    } onCancel: {
      extractionTask.cancel()
    }

    state = .extractingAudio(progress: 1.0, fileName: fileName)
    return extractedURL
  }

  private func throwIfCancellationRequested() throws {
    if cancellationRequested {
      throw CancellationError()
    }
  }

  private func publishTranscribingProgressIfNeeded(_ progress: Double, fileName: String) {
    guard case let .transcribing(currentProgress, currentFileName) = state,
      currentFileName == fileName
    else {
      return
    }

    let clampedProgress = min(max(progress, 0), 1)
    let percentBucket = Int(clampedProgress * 100)

    if let lastPublishedTranscriptionProgressPercent,
      percentBucket <= lastPublishedTranscriptionProgressPercent
    {
      return
    }

    let currentPercent = Int(min(max(currentProgress, 0), 1) * 100)
    guard percentBucket != currentPercent else {
      return
    }

    lastPublishedTranscriptionProgressPercent = percentBucket
    state = .transcribing(progress: Double(percentBucket) / 100, fileName: fileName)
  }

  private func notifyStateObservers() {
    let currentState = state
    for observer in stateObservers.values {
      observer(currentState)
    }
  }

  private func shouldExtractAudio(from mediaURL: URL) async throws -> Bool {
    let asset = AVURLAsset(url: mediaURL)
    let videoTracks = try await asset.loadTracks(withMediaType: .video)
    return !videoTracks.isEmpty
  }

  private nonisolated static func makePCMBuffer(from sampleBuffer: CMSampleBuffer) -> AVAudioPCMBuffer? {
    guard let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
          let streamDescriptionPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
    else {
      return nil
    }

    var streamDescription = streamDescriptionPointer.pointee
    guard let format = AVAudioFormat(streamDescription: &streamDescription) else {
      return nil
    }

    let sampleCount = CMSampleBufferGetNumSamples(sampleBuffer)
    guard sampleCount > 0,
          let pcmBuffer = AVAudioPCMBuffer(
            pcmFormat: format,
            frameCapacity: AVAudioFrameCount(sampleCount)
          )
    else {
      return nil
    }

    pcmBuffer.frameLength = AVAudioFrameCount(sampleCount)

    let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
      sampleBuffer,
      at: 0,
      frameCount: Int32(sampleCount),
      into: pcmBuffer.mutableAudioBufferList
    )

    guard status == 0 else {
      return nil
    }

    return pcmBuffer
  }
}

private extension TranscriptionManager {
  struct RuntimeConfig: Sendable {
    let modelName: String
    let downloadBase: URL
    let endpoint: String
    let language: String?

    @MainActor
    init(settings: TranscriptionSettings) {
      modelName = settings.modelName
      downloadBase = settings.modelDirectoryURL
      endpoint = settings.effectiveDownloadEndpoint
      language = settings.language == "auto" ? nil : settings.language
    }
  }
}

private actor TranscriptionRuntime {
  private var whisperKit: WhisperKit?
  private var loadedModelName: String?
  private var loadedModelDirectoryPath: String?

  private final class ProgressRelay: @unchecked Sendable {
    private let lock = NSLock()
    private var lastPublishedPercent = -1

    func consume(_ progress: Double) -> Double? {
      let clampedProgress = min(max(progress, 0), 1)
      let percentBucket = Int(clampedProgress * 100)

      lock.lock()
      defer { lock.unlock() }

      guard percentBucket > lastPublishedPercent else {
        return nil
      }

      lastPublishedPercent = percentBucket
      return Double(percentBucket) / 100
    }
  }

  func hasLoadedModel(named modelName: String, downloadBase: URL) -> Bool {
    let normalizedBasePath = downloadBase.standardizedFileURL.path
    return whisperKit != nil
      && loadedModelName == modelName
      && loadedModelDirectoryPath == normalizedBasePath
  }

  func loadModel(
    modelName: String,
    downloadBase: URL,
    endpoint: String
  ) async throws {
    let normalizedBasePath = downloadBase.standardizedFileURL.path
    if whisperKit != nil,
      loadedModelName == modelName,
      loadedModelDirectoryPath == normalizedBasePath
    {
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

    do {
      whisperKit = try await WhisperKit(config)
      loadedModelName = modelName
      loadedModelDirectoryPath = normalizedBasePath
    } catch {
      whisperKit = nil
      loadedModelName = nil
      loadedModelDirectoryPath = nil
      throw error
    }
  }

  func invalidateLoadedModel() {
    whisperKit = nil
    loadedModelName = nil
    loadedModelDirectoryPath = nil
  }

  func transcribe(
    audioPath: String,
    language: String?,
    audioFileID: UUID,
    onProgress: (@Sendable (Double) -> Void)? = nil
  ) async throws -> [SubtitleCue] {
    guard let whisperKit else {
      throw TranscriptionError.modelNotLoaded
    }

    let options = DecodingOptions(language: language)
    let progressRelay = ProgressRelay()
    let results = try await whisperKit.transcribe(
      audioPath: audioPath,
      decodeOptions: options,
      callback: { [whisperKit, progressRelay] _ in
        guard let onProgress else {
          return nil
        }

        let fractionCompleted = whisperKit.progress.fractionCompleted
        guard let quantizedProgress = progressRelay.consume(fractionCompleted) else {
          return nil
        }

        onProgress(quantizedProgress)
        return nil
      }
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

    let matchedByModelID = contents.first { url in
      let folderName = url.lastPathComponent
      guard let bestMatch = knownModels.first(where: { folderName.contains($0) }) else {
        return false
      }
      return bestMatch == modelName
    }

    if let matchedByModelID {
      return matchedByModelID.path
    }

    let fallbackByExactName = contents.first { url in
      url.lastPathComponent == modelName
    }

    return fallbackByExactName?.path
  }
}

// MARK: - Errors

enum TranscriptionError: LocalizedError {
  case modelNotLoaded
  case audioExtractionFailed(String)

  var errorDescription: String? {
    switch self {
    case .modelNotLoaded:
      return "WhisperKit model is not loaded"
    case let .audioExtractionFailed(reason):
      return "Audio extraction failed: \(reason)"
    }
  }
}
