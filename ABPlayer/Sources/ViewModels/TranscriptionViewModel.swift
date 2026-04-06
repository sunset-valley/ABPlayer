import Foundation
import SwiftData
import SwiftUI
import Observation

@Observable
@MainActor
final class TranscriptionViewModel {
  // MARK: - Dependencies
  var transcriptionManager: TranscriptionManager?
  var queueManager: TranscriptionQueueManager?
  var modelContext: ModelContext?
  var subtitleLoader: SubtitleLoader?
  
  // MARK: - Data Source
  var audioFile: ABFile?
  
  // MARK: - State
  var cachedCues: [SubtitleCue] = []
  var hasCheckedCache: Bool = false
  var isLoadingCache: Bool = false

  private var loadCachedTask: Task<Void, Never>?
  
  // MARK: - Persistence
  var subtitleFontSize: Double {
    didSet {
      UserDefaults.standard.set(subtitleFontSize, forKey: UserDefaultsKey.subtitleFontSize)
    }
  }
  
  // MARK: - Initialization
  init() {
    let storedSize = UserDefaults.standard.double(forKey: UserDefaultsKey.subtitleFontSize)
    self.subtitleFontSize = storedSize > 0 ? storedSize : 16.0
  }
  
  // MARK: - Setup
  func setup(
    audioFile: ABFile,
    transcriptionManager: TranscriptionManager,
    queueManager: TranscriptionQueueManager,
    modelContext: ModelContext,
    subtitleLoader: SubtitleLoader
  ) {
    let didChangeFile = self.audioFile?.id != audioFile.id
    if didChangeFile {
      resetState()
    }

    self.audioFile = audioFile
    self.transcriptionManager = transcriptionManager
    self.queueManager = queueManager
    self.modelContext = modelContext
    self.subtitleLoader = subtitleLoader
    
    // Reset state if file changed or not loaded
    if cachedCues.isEmpty && !hasCheckedCache && !isLoadingCache {
      Task { await loadCachedTranscription() }
    }
  }
  
  func resetState() {
    loadCachedTask?.cancel()
    loadCachedTask = nil

    cachedCues = []
    hasCheckedCache = false
    isLoadingCache = false
    transcriptionManager?.reset()
  }
  
  // MARK: - Logic
  
  var currentTask: TranscriptionTask? {
    guard let fileId = audioFile?.id, let queueManager = queueManager else { return nil }
    return queueManager.getTask(for: fileId)
  }
  
  func loadCachedTranscription() async {
    guard let audioFile = audioFile, let subtitleLoader = subtitleLoader else { return }

    loadCachedTask?.cancel()
    let task = Task { [audioFile, subtitleLoader] in
      isLoadingCache = true
      defer { isLoadingCache = false }

      try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
      guard !Task.isCancelled else { return }

      let cues = await subtitleLoader.loadSubtitles(for: audioFile)
      guard !Task.isCancelled else { return }

      cachedCues = cues
      hasCheckedCache = true
    }

    loadCachedTask = task
    await task.value
  }
  
  func startTranscription() {
    guard let audioFile = audioFile, let queueManager = queueManager, let modelContext = modelContext else { return }
    
    // Set modelContext on queue manager if needed
    if queueManager.modelContext == nil {
      queueManager.modelContext = modelContext
    }
    // Enqueue the transcription task
    queueManager.enqueue(audioFile: audioFile)
  }

  func retryTranscriptionFromStart() {
    guard let audioFile = audioFile, let queueManager = queueManager, let modelContext = modelContext else {
      return
    }

    if queueManager.modelContext == nil {
      queueManager.modelContext = modelContext
    }

    queueManager.enqueue(audioFile: audioFile, forceTranscription: true)
  }
  
  func clearAndRetranscribe() async {
    retryTranscriptionFromStart()
  }

  func updateSubtitle(cueID: UUID, subtitle: String) async {
    guard let audioFile = audioFile, let subtitleLoader = subtitleLoader else { return }

    if let updatedCues = await subtitleLoader.updateSubtitle(
      for: audioFile,
      cueID: cueID,
      subtitle: subtitle
    ) {
      cachedCues = updatedCues
    }
  }

}
