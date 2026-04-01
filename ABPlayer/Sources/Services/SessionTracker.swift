import Foundation
import OSLog
import Observation
import SwiftData

/// Background actor to handle SwiftData operations for listening sessions.
/// This ensures all database operations happen off the main thread.
@ModelActor
actor SessionRecorder {
  private var currentSessionID: PersistentIdentifier?

  /// Start a new session on the background context.
  @discardableResult
  private func createSession() -> ListeningSession? {
    let session = ListeningSession()
    modelContext.insert(session)
    do {
      try modelContext.save()
      currentSessionID = session.persistentModelID
      return session
    } catch {
      Logger.data.error("[SessionRecorder] Failed to start session: \(error)")
      currentSessionID = nil
      return nil
    }
  }

  /// Start a new session on the background context.
  func startNewSession() {
    _ = createSession()
  }

  /// Add listening time to the current session
  func addTime(_ delta: Double) {
    guard delta > 0 else { return }

    guard let id = currentSessionID,
      let session = modelContext.model(for: id) as? ListeningSession,
      !session.isDeleted
    else {
      Logger.data.warning("[SessionRecorder] No active session, skipping addTime")
      return
    }

    do {
      session.duration += delta
      try modelContext.save()
    } catch {
      Logger.data.error("[SessionRecorder] Failed to save time update: \(error)")
      // If save fails, the session may be corrupted - reset for next time
      currentSessionID = nil
    }
  }

  /// End the current session
  func endSession() {
    guard let id = currentSessionID else { return }

    // Try to fetch the session - it may have been invalidated
    guard let session = modelContext.model(for: id) as? ListeningSession else {
      Logger.data.warning("[SessionRecorder] Cannot end session - already invalidated")
      currentSessionID = nil
      return
    }

    if session.isDeleted {
      Logger.data.warning("[SessionRecorder] Cannot end session - already invalidated")
      currentSessionID = nil
      return
    }

    do {
      session.endedAt = Date()
      try modelContext.save()
    } catch {
      Logger.data.error("[SessionRecorder] Failed to save session end: \(error)")
    }
    currentSessionID = nil
  }
}

/// Tracks listening sessions and persists playback progress.
/// This class is @MainActor to ensure safe UI binding interactions.
@MainActor
@Observable
final class SessionTracker {
  private var recorder: SessionRecorder?
  private var recorderTask: Task<Void, Never>?

  private let warmupThreshold: Double
  private let idleTimeout: TimeInterval

  // Buffered state.
  private var bufferedListeningTime: Double = 0
  private var lastCommitTime: Date = Date()
  private let commitInterval: TimeInterval = 5

  // UI state.
  private var _totalSeconds: Double = 0
  private(set) var displaySeconds: Int = 0
  private var isSessionActive = false
  private var isCurrentlyPlaying = false
  private var warmupPlayedSeconds: Double = 0
  private var idleEndTask: Task<Void, Never>?

  init(
    warmupThreshold: Double = 5,
    idleTimeout: TimeInterval = 5
  ) {
    self.warmupThreshold = warmupThreshold
    self.idleTimeout = idleTimeout
  }

  init(modelContainer: ModelContainer) {
    warmupThreshold = 5
    idleTimeout = 5
    self.recorder = SessionRecorder(modelContainer: modelContainer)
  }

  init(
    modelContainer: ModelContainer,
    warmupThreshold: Double,
    idleTimeout: TimeInterval
  ) {
    self.warmupThreshold = warmupThreshold
    self.idleTimeout = idleTimeout
    self.recorder = SessionRecorder(modelContainer: modelContainer)
  }

  /// Initialize the recorder with a ModelContainer.
  func setModelContainer(_ container: ModelContainer) {
    self.recorder = SessionRecorder(modelContainer: container)
  }

  /// Drive session state from playback state changes.
  func handlePlaybackStateChanged(isPlaying: Bool) {
    guard isCurrentlyPlaying != isPlaying else { return }

    isCurrentlyPlaying = isPlaying

    if isPlaying {
      idleEndTask?.cancel()
      idleEndTask = nil
      return
    }

    persistProgress()
    scheduleIdleSessionEnd()
  }

  /// Record one playback tick in seconds while media is playing.
  func recordPlaybackTick(_ delta: Double) {
    guard isCurrentlyPlaying else { return }
    guard delta > 0 else { return }

    if isSessionActive {
      appendRecordedDuration(delta)
      return
    }

    warmupPlayedSeconds += delta
    if warmupPlayedSeconds >= warmupThreshold {
      startSession(withInitialDuration: warmupPlayedSeconds)
      warmupPlayedSeconds = 0
    }
  }

  private func startSession(withInitialDuration initialDuration: Double) {
    guard !isSessionActive else { return }
    guard initialDuration > 0 else { return }

    isSessionActive = true
    bufferedListeningTime = 0
    lastCommitTime = Date()
    enqueueRecorderOperation { recorder in
      await recorder?.startNewSession()
    }
    appendRecordedDuration(initialDuration)
  }

  private func appendRecordedDuration(_ delta: Double) {
    guard delta > 0 else { return }

    _totalSeconds += delta

    let newDisplaySeconds = Int(_totalSeconds)
    if newDisplaySeconds != displaySeconds {
      displaySeconds = newDisplaySeconds
    }

    bufferedListeningTime += delta

    let now = Date()
    if now.timeIntervalSince(lastCommitTime) >= commitInterval {
      commitPendingTime()
    }
  }

  /// Commit currently buffered time to the background actor
  private func commitPendingTime() {
    let amountToCommit = drainBufferedTime()
    guard amountToCommit > 0 else { return }

    enqueueRecorderOperation { recorder in
      await recorder?.addTime(amountToCommit)
    }
  }

  private func drainBufferedTime() -> Double {
    guard bufferedListeningTime > 0 else { return 0 }
    let amount = bufferedListeningTime
    bufferedListeningTime = 0
    lastCommitTime = Date()
    return amount
  }

  /// Persist current playback progress (called on pause/stop/background)
  func persistProgress() {
    commitPendingTime()
  }

  /// End the current session if playback is currently idle.
  func endSessionIfIdle() {
    guard !isCurrentlyPlaying else { return }
    endSession()
  }

  /// End the current session immediately.
  func endSession() {
    idleEndTask?.cancel()
    idleEndTask = nil
    warmupPlayedSeconds = 0

    guard isSessionActive else { return }

    let amountToCommit = drainBufferedTime()
    isSessionActive = false
    warmupPlayedSeconds = 0
    _totalSeconds = 0
    displaySeconds = 0

    enqueueRecorderOperation { recorder in
      if amountToCommit > 0 {
        await recorder?.addTime(amountToCommit)
      }
      await recorder?.endSession()
    }
  }

  func waitForRecorderTasksForTesting() async {
    await recorderTask?.value
  }

  private func scheduleIdleSessionEnd() {
    idleEndTask?.cancel()
    idleEndTask = Task { [weak self] in
      guard let self else { return }

      let nanos = UInt64(self.idleTimeout * 1_000_000_000)
      do {
        try await Task.sleep(nanoseconds: nanos)
      } catch {
        return
      }
      self.handleIdleTimeout()
    }
  }

  private func handleIdleTimeout() {
    guard !isCurrentlyPlaying else { return }
    warmupPlayedSeconds = 0
    endSession()
  }

  private func enqueueRecorderOperation(
    _ operation: @escaping @Sendable (SessionRecorder?) async -> Void
  ) {
    let previousTask = recorderTask
    let recorder = self.recorder
    recorderTask = Task {
      if let previousTask {
        await previousTask.value
      }
      await operation(recorder)
    }
  }
}
