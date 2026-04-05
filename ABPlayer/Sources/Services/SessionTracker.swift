import Foundation
import OSLog
import Observation
import SwiftData

/// Background actor to handle SwiftData operations for listening sessions.
/// This ensures all database operations happen off the main thread.
@ModelActor
actor SessionRecorder {
  private var currentSessionID: PersistentIdentifier?
  private let orphanMergeGapSeconds: TimeInterval = 60

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

  /// Repair stale orphan sessions left open by prior app runs.
  func repairOrphanSessions(now: Date = Date()) {
    let descriptor = FetchDescriptor<ListeningSession>(
      sortBy: [SortDescriptor(\ListeningSession.startedAt, order: .forward)]
    )

    guard let sessions = try? modelContext.fetch(descriptor), !sessions.isEmpty else {
      return
    }

    var didMutate = false
    var repairedOrphanIDs: Set<PersistentIdentifier> = []

    for (index, session) in sessions.enumerated() {
      guard session.endedAt == nil else { continue }

      var repairedEnd = session.startedAt.addingTimeInterval(max(0, session.duration))
      if let nextSession = sessions[(index + 1)...].first(where: { $0.startedAt > session.startedAt }) {
        repairedEnd = min(repairedEnd, nextSession.startedAt)
      }

      if repairedEnd <= session.startedAt {
        modelContext.delete(session)
        didMutate = true
        continue
      }

      session.endedAt = min(repairedEnd, now)
      repairedOrphanIDs.insert(session.persistentModelID)
      didMutate = true
    }

    if !repairedOrphanIDs.isEmpty {
      if let refreshedSessions = try? modelContext.fetch(descriptor) {
        var previousRepairedSession: ListeningSession?

        for session in refreshedSessions {
          guard repairedOrphanIDs.contains(session.persistentModelID) else {
            previousRepairedSession = nil
            continue
          }

          guard let sessionEnd = session.endedAt, sessionEnd > session.startedAt else {
            modelContext.delete(session)
            didMutate = true
            continue
          }

          if let previousRepairedSession, let previousEnd = previousRepairedSession.endedAt {
            let gap = session.startedAt.timeIntervalSince(previousEnd)
            if gap <= orphanMergeGapSeconds {
              previousRepairedSession.endedAt = max(previousEnd, sessionEnd)
              previousRepairedSession.duration = max(0, previousRepairedSession.duration) + max(0, session.duration)
              modelContext.delete(session)
              didMutate = true
              continue
            }
          }

          previousRepairedSession = session
        }
      }
    }

    guard didMutate else { return }
    do {
      try modelContext.save()
    } catch {
      Logger.data.error("[SessionRecorder] Failed to repair orphan sessions: \(error)")
    }
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
  private var didScheduleOrphanCleanup = false

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
    scheduleOrphanCleanupIfNeeded()
  }

  init(
    modelContainer: ModelContainer,
    warmupThreshold: Double,
    idleTimeout: TimeInterval
  ) {
    self.warmupThreshold = warmupThreshold
    self.idleTimeout = idleTimeout
    self.recorder = SessionRecorder(modelContainer: modelContainer)
    scheduleOrphanCleanupIfNeeded()
  }

  /// Initialize the recorder with a ModelContainer.
  func setModelContainer(_ container: ModelContainer) {
    self.recorder = SessionRecorder(modelContainer: container)
    didScheduleOrphanCleanup = false
    scheduleOrphanCleanupIfNeeded()
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

  /// End active session and wait until recorder queue is fully flushed.
  func endSessionAndWait() async {
    endSession()
    await recorderTask?.value
  }

  /// Best-effort shutdown hook for app lifecycle.
  func shutdownAndWait() async {
    await endSessionAndWait()
  }

  /// Trigger orphan-session cleanup and wait for completion.
  func repairOrphanSessionsNow() async {
    enqueueRecorderOperation { recorder in
      await recorder?.repairOrphanSessions()
    }
    await recorderTask?.value
  }

  func endSessionAndWaitForTesting() async {
    await endSessionAndWait()
  }

  func runOrphanCleanupForTesting() async {
    await repairOrphanSessionsNow()
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

  private func scheduleOrphanCleanupIfNeeded() {
    guard !didScheduleOrphanCleanup else { return }
    didScheduleOrphanCleanup = true

    enqueueRecorderOperation { recorder in
      await recorder?.repairOrphanSessions()
    }
  }
}
