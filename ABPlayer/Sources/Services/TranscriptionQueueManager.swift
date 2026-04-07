import Foundation
import OSLog
import Observation
import SwiftData

/// Status of a transcription task
enum TranscriptionTaskStatus: Equatable {
  case queued
  case checkingExistingSubtitles
  case loadingExistingSubtitles
  case downloading(progress: Double)
  case loading
  case extractingAudio(progress: Double)
  case transcribing(progress: Double)
  case savingSubtitles
  case reloadingSubtitles
  case completed
  case failed(String)
  case cancelled

  var isInProgress: Bool {
    switch self {
    case .queued,
         .checkingExistingSubtitles,
         .loadingExistingSubtitles,
         .downloading,
         .loading,
         .extractingAudio,
         .transcribing,
         .savingSubtitles,
         .reloadingSubtitles:
      return true
    case .completed, .failed, .cancelled:
      return false
    }
  }
}

/// A transcription task in the queue
struct TranscriptionTask: Identifiable, Equatable {
  let id: UUID
  let audioFileId: UUID
  let audioFileName: String
  let audioRelativePath: String
  /// Legacy field retained for store compatibility with historical queue semantics.
  /// Managed-library mode does not consume per-file bookmark data.
  let bookmarkData: Data
  let forceTranscription: Bool
  var status: TranscriptionTaskStatus

  init(
    id: UUID = UUID(),
    audioFileId: UUID,
    audioFileName: String,
    audioRelativePath: String,
    bookmarkData: Data = Data(),
    forceTranscription: Bool = false,
    status: TranscriptionTaskStatus = .queued
  ) {
    self.id = id
    self.audioFileId = audioFileId
    self.audioFileName = audioFileName
    self.audioRelativePath = audioRelativePath
    self.bookmarkData = bookmarkData
    self.forceTranscription = forceTranscription
    self.status = status
  }
}

/// Manages transcription queue - processes one audio file at a time
@MainActor
@Observable
final class TranscriptionQueueManager {
  private let transcriptionManager: TranscriptionManager
  private let settings: TranscriptionSettings
  private let subtitleLoader: SubtitleLoader

  /// All tasks (pending + completed)
  private(set) var tasks: [TranscriptionTask] = []

  /// Current processing task
  private var processingTask: Task<Void, Never>?

  /// ModelContext for saving results
  var modelContext: ModelContext?
  let librarySettings: LibrarySettings

  init(
    transcriptionManager: TranscriptionManager,
    settings: TranscriptionSettings,
    subtitleLoader: SubtitleLoader,
    librarySettings: LibrarySettings
  ) {
    self.transcriptionManager = transcriptionManager
    self.settings = settings
    self.subtitleLoader = subtitleLoader
    self.librarySettings = librarySettings
  }

  /// Get task for a specific audio file
  func getTask(for audioFileId: UUID) -> TranscriptionTask? {
    tasks.first { $0.audioFileId == audioFileId }
  }

  /// Enqueue a new transcription task
  func enqueue(audioFile: ABFile, forceTranscription: Bool = false) {
    if let existingIndex = tasks.firstIndex(where: { $0.audioFileId == audioFile.id }) {
      if tasks[existingIndex].status.isInProgress {
        return
      }
      tasks.remove(at: existingIndex)
    }

    let task = TranscriptionTask(
      audioFileId: audioFile.id,
      audioFileName: audioFile.displayName,
      audioRelativePath: audioFile.relativePath,
      bookmarkData: Data(),
      forceTranscription: forceTranscription
    )

    tasks.append(task)

    // Start processing if not already running
    if processingTask == nil {
      processingTask = Task {
        await processQueue()
      }
    }
  }

  func retryTask(id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }
    guard case .failed = tasks[index].status else { return }

    tasks[index].status = .queued

    if processingTask == nil {
      processingTask = Task {
        await processQueue()
      }
    }
  }

  func cancelTask(id: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == id }) else { return }

    let task = tasks[index]
    switch task.status {
    case .queued:
      tasks.remove(at: index)
    case .checkingExistingSubtitles,
         .loadingExistingSubtitles,
         .downloading,
         .loading,
         .extractingAudio,
         .transcribing,
         .savingSubtitles,
         .reloadingSubtitles:
      tasks.remove(at: index)
      transcriptionManager.cancelDownload()
      transcriptionManager.cancelTranscription()
    default:
      break
    }
  }

  /// Remove a task from the list
  func removeTask(id: UUID) {
    tasks.removeAll { $0.id == id }
  }

  // MARK: - Private

  private func processQueue() async {
    while let nextTask = nextPendingTask() {
      await processTask(nextTask)
    }
    processingTask = nil
  }

  private func nextPendingTask() -> TranscriptionTask? {
    tasks.first { $0.status == .queued }
  }

  private func processTask(_ task: TranscriptionTask) async {
    guard tasks.contains(where: { $0.id == task.id }) else { return }

    do {
      // Resolve URL
      let url = librarySettings.mediaFileURL(forRelativePath: task.audioRelativePath)

      // Track transcription manager state changes
      let observerID = transcriptionManager.addStateObserver { [weak self] state in
        guard let self else { return }
        self.updateTask(taskId: task.id, from: state)
      }
      defer { transcriptionManager.removeStateObserver(observerID) }

      updateTaskStatus(.checkingExistingSubtitles, for: task.id)
      if !task.forceTranscription {
        let hasExistingSubtitles = try await loadExistingSubtitlesIfPresent(
          audioURL: url,
          audioFileID: task.audioFileId,
          taskID: task.id
        )

        if hasExistingSubtitles {
          updateTaskStatus(.completed, for: task.id)
          transcriptionManager.reset()
          return
        }
      }

      // Perform transcription
      let cues = try await transcriptionManager.transcribe(
        audioFileID: task.audioFileId,
        audioURL: url,
        settings: settings
      )

      updateTaskStatus(.savingSubtitles, for: task.id)
      let commitContext = try await stageAndCommitSubtitles(
        audioFileID: task.audioFileId,
        audioRelativePath: task.audioRelativePath,
        cues: cues
      )

      defer {
        if let backupURL = commitContext.backupURL {
          try? FileManager.default.removeItem(at: backupURL)
        }
      }

      updateTaskStatus(.reloadingSubtitles, for: task.id)
      do {
        try await reloadCommittedSubtitles(
          from: commitContext.srtURL,
          audioFileID: task.audioFileId,
          requireNonEmptyCues: true
        )
      } catch {
        if let backupURL = commitContext.backupURL {
          try? replaceSubtitleFile(at: commitContext.srtURL, with: backupURL)
        } else {
          try? FileManager.default.removeItem(at: commitContext.srtURL)
        }
        _ = await subtitleLoader.loadSubtitlesResult(from: commitContext.srtURL, audioFileID: task.audioFileId)
        throw error
      }

      await persistTranscriptionMetadata(
        audioFileId: task.audioFileId,
        audioFileName: task.audioFileName
      )

      updateTaskStatus(.completed, for: task.id)

      transcriptionManager.reset()

    } catch is CancellationError {
      tasks.removeAll { $0.id == task.id }
      transcriptionManager.reset()
    } catch {
      if let idx = tasks.firstIndex(where: { $0.id == task.id }) {
        tasks[idx].status = .failed(error.localizedDescription)
      }
      transcriptionManager.reset()
    }
  }

  private struct SubtitleCommitContext {
    let srtURL: URL
    let backupURL: URL?
  }

  private func updateTaskStatus(_ status: TranscriptionTaskStatus, for taskID: UUID) {
    guard let index = tasks.firstIndex(where: { $0.id == taskID }) else { return }
    if tasks[index].status != status {
      tasks[index].status = status
    }
  }

  private func loadExistingSubtitlesIfPresent(
    audioURL: URL,
    audioFileID: UUID,
    taskID: UUID
  ) async throws -> Bool {
    let srtURL = audioURL.deletingPathExtension().appendingPathExtension("srt")
    guard FileManager.default.fileExists(atPath: srtURL.path) else {
      return false
    }

    updateTaskStatus(.loadingExistingSubtitles, for: taskID)

    let loadResult = await subtitleLoader.loadSubtitlesResult(from: srtURL, audioFileID: audioFileID)
    switch loadResult {
    case let .loaded(cues):
      return !cues.isEmpty
    case .notFound:
      return false
    case let .failed(errorMessage):
      throw QueueError.failedToLoadExistingSubtitles(errorMessage)
    }
  }

  private func updateTask(taskId: UUID, from state: TranscriptionState) {
    guard let index = tasks.firstIndex(where: { $0.id == taskId }) else { return }

    switch state {
    case .downloading(let progress, _):
      if tasks[index].status != .downloading(progress: progress) {
        tasks[index].status = .downloading(progress: progress)
      }
    case .loading:
      if tasks[index].status != .loading {
        tasks[index].status = .loading
      }
    case .extractingAudio(let progress, _):
      if tasks[index].status != .extractingAudio(progress: progress) {
        tasks[index].status = .extractingAudio(progress: progress)
      }
    case .transcribing(let progress, _):
      if tasks[index].status != .transcribing(progress: progress) {
        tasks[index].status = .transcribing(progress: progress)
      }
    default:
      break
    }
  }

  private func stageAndCommitSubtitles(
    audioFileID: UUID,
    audioRelativePath: String,
    cues: [SubtitleCue]
  ) async throws -> SubtitleCommitContext {
    let audioURL = librarySettings.mediaFileURL(forRelativePath: audioRelativePath)

    let srtURL = audioURL.deletingPathExtension().appendingPathExtension("srt")
    let stagedURL = siblingTemporarySubtitleURL(for: srtURL, suffix: "staged-\(audioFileID.uuidString)-\(UUID().uuidString)")

    var backupURL: URL?

    defer {
      try? FileManager.default.removeItem(at: stagedURL)
    }

    do {
      try await Task.detached(priority: .utility) {
        try SubtitleParser.writeSRT(cues: cues, to: stagedURL)
      }.value
    } catch {
      throw QueueError.failedToSaveSubtitles(error.localizedDescription)
    }

    do {
      let stagedCues = try await Task.detached(priority: .utility) {
        try SubtitleParser.parse(from: stagedURL, audioFileID: audioFileID)
      }.value

      guard !stagedCues.isEmpty else {
        throw QueueError.failedToSaveSubtitles("Transcription produced no subtitle cues")
      }
    } catch {
      if let queueError = error as? QueueError {
        throw queueError
      }
      throw QueueError.failedToSaveSubtitles("Failed to validate staged subtitles: \(error.localizedDescription)")
    }

    if FileManager.default.fileExists(atPath: srtURL.path) {
      let backup = siblingTemporarySubtitleURL(for: srtURL, suffix: "backup-\(audioFileID.uuidString)-\(UUID().uuidString)")
      do {
        try FileManager.default.copyItem(at: srtURL, to: backup)
        backupURL = backup
      } catch {
        throw QueueError.failedToSaveSubtitles("Failed to backup existing subtitles: \(error.localizedDescription)")
      }
    }

    do {
      try replaceSubtitleFile(at: srtURL, with: stagedURL)
    } catch {
      throw QueueError.failedToSaveSubtitles(error.localizedDescription)
    }

    return SubtitleCommitContext(srtURL: srtURL, backupURL: backupURL)
  }

  private func siblingTemporarySubtitleURL(for srtURL: URL, suffix: String) -> URL {
    let baseName = srtURL.deletingPathExtension().lastPathComponent
    let fileName = ".\(baseName).\(suffix).srt"
    return srtURL.deletingLastPathComponent().appendingPathComponent(fileName)
  }

  private func replaceSubtitleFile(at destinationURL: URL, with sourceURL: URL) throws {
    if FileManager.default.fileExists(atPath: destinationURL.path) {
      do {
        _ = try FileManager.default.replaceItemAt(
          destinationURL,
          withItemAt: sourceURL,
          backupItemName: nil,
          options: []
        )
      } catch {
        try FileManager.default.removeItem(at: destinationURL)
        try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
      }
    } else {
      try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
    }
  }

  private func reloadCommittedSubtitles(
    from srtURL: URL,
    audioFileID: UUID,
    requireNonEmptyCues: Bool = false
  ) async throws {
    let loadResult = await subtitleLoader.loadSubtitlesResult(from: srtURL, audioFileID: audioFileID)
    switch loadResult {
    case let .loaded(cues):
      if requireNonEmptyCues, cues.isEmpty {
        throw QueueError.failedToReloadSubtitles("Subtitle file was saved but contains no cues")
      }
    case .notFound:
      throw QueueError.failedToReloadSubtitles("Saved subtitle file not found")
    case let .failed(errorMessage):
      throw QueueError.failedToReloadSubtitles(errorMessage)
    }
  }

  private func persistTranscriptionMetadata(
    audioFileId: UUID,
    audioFileName: String
  ) async {
    guard let context = modelContext else { return }

    let audioFileIdString = audioFileId.uuidString
    let descriptor = FetchDescriptor<Transcription>(
      predicate: #Predicate { $0.audioFileId == audioFileIdString }
    )

    if let existing = try? context.fetch(descriptor).first {
      existing.createdAt = Date()
      existing.modelUsed = settings.modelName
      existing.language = settings.language
    } else {
      let cache = Transcription(
        audioFileId: audioFileIdString,
        audioFileName: audioFileName,
        modelUsed: settings.modelName,
        language: settings.language == "auto" ? nil : settings.language
      )
      context.insert(cache)
    }

    do {
      try context.save()
    } catch {
      Logger.data.error("⚠️ Failed to save transcription cache: \(error.localizedDescription)")
    }

    // Update hasTranscription flag
    let audioDescriptor = FetchDescriptor<ABFile>(
      predicate: #Predicate { $0.id == audioFileId }
    )
    if let audioFile = try? context.fetch(audioDescriptor).first {
      audioFile.hasTranscriptionRecord = true
      do {
        try context.save()
      } catch {
        Logger.data.error("⚠️ Failed to save hasTranscriptionRecord flag: \(error.localizedDescription)")
      }
    }
  }

}

private enum QueueError: LocalizedError {
  case failedToLoadExistingSubtitles(String)
  case failedToSaveSubtitles(String)
  case failedToReloadSubtitles(String)

  var errorDescription: String? {
    switch self {
    case let .failedToLoadExistingSubtitles(message):
      return "Failed to load existing subtitles: \(message)"
    case let .failedToSaveSubtitles(message):
      return "Failed to save subtitles: \(message)"
    case let .failedToReloadSubtitles(message):
      return "Failed to reload subtitles: \(message)"
    }
  }
}
