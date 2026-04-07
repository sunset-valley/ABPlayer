import AVFoundation
import Foundation
import OSLog
import Observation

// MARK: - Observable UI State (MainActor)

@MainActor
@Observable
final class PlayerManager {
  private let _engine: any PlayerEngineProtocol
  let librarySettings: LibrarySettings

  init(librarySettings: LibrarySettings, engine: (any PlayerEngineProtocol)? = nil) {
    self.librarySettings = librarySettings
    self._engine = engine ?? PlayerEngine()
  }

  private(set) weak var player: AVPlayer?

  private var loadingFileID: UUID?

  var currentFile: ABFile?
  var sessionTracker: SessionTracker?

  var isPlaying: Bool = false
  var currentTime: Double = 0
  var duration: Double = 0
  var volume: Float = 1.0

  var pointA: Double?
  var pointB: Double?

  var isLoopEnabled: Bool = true

  var playbackQueue = PlaybackQueue()

  var loopMode: PlaybackQueue.LoopMode {
    get { playbackQueue.loopMode }
    set { playbackQueue.loopMode = newValue }
  }

  var currentSegmentID: UUID?

  var onSegmentSaved: ((LoopSegment) -> Void)?

  var onPlaybackEnded: ((ABFile?) -> Void)?

  var playerSettings: PlayerSettings?

  private var lastPersistedTime: Double = 0
  private var endOfFileTask: Task<Void, Never>?
  private var loadAudioTask: Task<Void, Never>?
  private var playbackTimeObservers: [UUID: @MainActor (Double) -> Void] = [:]
  private var sleepActivity: NSObjectProtocol?

  var isSleepPreventionActiveForTest: Bool {
    sleepActivity != nil
  }

  var hasValidLoopRange: Bool {
    guard let pointA, let pointB else {
      return false
    }

    return pointB > pointA
  }

  var isLooping: Bool {
    isLoopEnabled && hasValidLoopRange
  }

  func clearPlayer() async {
    sessionTracker?.handlePlaybackStateChanged(isPlaying: false)
    await sessionTracker?.endSessionAndWait()
    isPlaying = false
    updateSleepPrevention()
    player = nil
    await _engine.teardown()
  }

  deinit {
    Task { [weak self] in
      await self?.clearPlayer()
    }
  }

  // MARK: - Public API

  func load(audioFile: ABFile, fromStart: Bool = false) async {
    let fileURL = librarySettings.mediaFileURL(for: audioFile)
    guard FileManager.default.fileExists(atPath: fileURL.path) else {
      Logger.audio.error("Load aborted: File missing for \(audioFile.displayName)")
      return
    }

    if let cached = audioFile.cachedDuration, cached > 0 {
      duration = cached
    }

    let fileID = audioFile.id
    loadingFileID = fileID
    audioFile.loadError = nil

    currentFile = audioFile
    currentTime = 0
    isPlaying = false
    updateSleepPrevention()
    clearLoop()
    lastPersistedTime = 0

    endOfFileTask?.cancel()
    endOfFileTask = nil

    let resumeTime = fromStart ? 0 : audioFile.currentPlaybackPosition

    do {
      let playerItem = try await _engine.load(
        fileURL: fileURL,
        resumeTime: resumeTime,
        onDurationLoaded: { [weak self] loadedDuration in
          guard let self, self.loadingFileID == fileID else { return }
          self.duration = loadedDuration
          audioFile.cachedDuration = loadedDuration
        },
        onTimeUpdate: { [weak self] seconds in
          guard let self, self.currentFile?.id == fileID else { return }
          self.handleTimeUpdate(seconds)
        },
        onLoopCheck: { [weak self] seconds in
          guard let self, self.currentFile?.id == fileID else { return }
          self.handleLoopCheck(seconds)
        },
        onPlaybackStateChange: { [weak self] isPlaying in
          guard let self, self.currentFile?.id == fileID else { return }
          self.handlePlaybackStateUpdate(isPlaying)
        },
        onPlayerReady: { [weak self] player in
          guard let self, self.loadingFileID == fileID else { return }
          self.player = player
        }
      )

      guard loadingFileID == fileID else {
        return
      }

      if let item = playerItem {
        self.endOfFileTask = Task { [weak self] in
          for await _ in NotificationCenter.default.notifications(
            named: .AVPlayerItemDidPlayToEndTime,
            object: item
          ) {
            guard let self else { return }
            guard self.currentFile?.id == fileID else { continue }
            await self.handlePlaybackEnded()
          }
        }
      }

      if resumeTime > 0 {
        currentTime = resumeTime
        lastPersistedTime = resumeTime
      }

      await _engine.setVolume(volume)
    } catch {
      if loadingFileID == fileID {
        audioFile.loadError = error.localizedDescription
        Logger.audio.error("Failed to load audio file: \(error, privacy: .public)")
      }
    }
  }

  func play(fromStart: Bool = false) async {
    guard !isPlaying else { return }
    guard currentFile != nil else { return }

    if fromStart {
      await seek(to: 0)
    }
    let success = await _engine.play()
    if success {
      self.isPlaying = true
      updateSleepPrevention()
      sessionTracker?.handlePlaybackStateChanged(isPlaying: true)
      if let file = self.currentFile {
        touchPlaybackRecord(for: file)
      }
    }
  }

  func pause() async {
    guard isPlaying else { return }

    await _engine.pause()
    self.isPlaying = false
    updateSleepPrevention()
    self.sessionTracker?.handlePlaybackStateChanged(isPlaying: false)
  }

  func togglePlayPause() async {
    guard isPlaying || currentFile != nil else { return }

    let startTime = CFAbsoluteTimeGetCurrent()
    Logger.audio.debug("[Performance] togglePlayPause() called, isPlaying: \(self.isPlaying)")

    if isPlaying {
      isPlaying = false
      updateSleepPrevention()
      sessionTracker?.handlePlaybackStateChanged(isPlaying: false)
      let uiUpdateTime = CFAbsoluteTimeGetCurrent()
      Logger.audio.debug(
        "[Performance] isPlaying = false (immediate) after \((uiUpdateTime - startTime) * 1000)ms")

      player?.pause()
      let pauseTime = CFAbsoluteTimeGetCurrent()
      Logger.audio.debug(
        "[Performance] player.pause() (sync) completed after \((pauseTime - uiUpdateTime) * 1000)ms"
      )

      Logger.audio.debug(
        "[Performance] User perceives pause after \((CFAbsoluteTimeGetCurrent() - startTime) * 1000)ms"
      )

      await _engine.syncPauseState()
      Logger.audio.debug(
        "[Performance] Background sync completed after \((CFAbsoluteTimeGetCurrent() - startTime) * 1000)ms"
      )
    } else {
      isPlaying = true
      updateSleepPrevention()
      sessionTracker?.handlePlaybackStateChanged(isPlaying: true)
      let uiUpdateTime = CFAbsoluteTimeGetCurrent()
      Logger.audio.debug(
        "[Performance] isPlaying = true (immediate) after \((uiUpdateTime - startTime) * 1000)ms")

      player?.play()
      let playTime = CFAbsoluteTimeGetCurrent()
      Logger.audio.debug(
        "[Performance] player.play() (sync) completed after \((playTime - uiUpdateTime) * 1000)ms")

      Logger.audio.debug(
        "[Performance] User perceives play after \((CFAbsoluteTimeGetCurrent() - startTime) * 1000)ms"
      )

      await _engine.syncPlayState()
      if let file = self.currentFile {
        touchPlaybackRecord(for: file)
      }
      Logger.audio.debug(
        "[Performance] Background sync completed after \((CFAbsoluteTimeGetCurrent() - startTime) * 1000)ms"
      )
    }
  }

  func seek(to time: Double) async {
    let maxTime: Double
    if duration > 0 {
      maxTime = duration
    } else {
      maxTime = time
    }

    let clampedTime = min(max(time, 0), maxTime)
    currentTime = clampedTime

    if clampedTime.isFinite && clampedTime >= 0 {
      currentFile?.currentPlaybackPosition = clampedTime
      lastPersistedTime = clampedTime
    }

    await _engine.seek(to: clampedTime)
  }

  func setVolume(_ volume: Float) async {
    self.volume = volume
    await _engine.setVolume(volume)
  }

  @discardableResult
  func addPlaybackTimeObserver(_ observer: @escaping @MainActor (Double) -> Void) -> UUID {
    let id = UUID()
    playbackTimeObservers[id] = observer
    return id
  }

  func removePlaybackTimeObserver(_ id: UUID) {
    playbackTimeObservers[id] = nil
  }

  private func notifyPlaybackTimeObservers(_ time: Double) {
    for observer in playbackTimeObservers.values {
      observer(time)
    }
  }

  // MARK: - Private Helpers

  private func touchPlaybackRecord(for file: ABFile) {
    if file.playbackRecord == nil {
      file.playbackRecord = PlaybackRecord(audioFile: file)
    }
    file.playbackRecord?.lastPlayedAt = Date()
  }

  // MARK: - Internal Handlers

  fileprivate func handleTimeUpdate(_ seconds: Double) {
    currentTime = seconds

    if abs(seconds - lastPersistedTime) >= 1 {
      currentFile?.currentPlaybackPosition = seconds
      lastPersistedTime = seconds
    }

    if isPlaying {
      notifyPlaybackTimeObservers(seconds)
      sessionTracker?.recordPlaybackTick(0.1)
    }
  }

  fileprivate func handleLoopCheck(_ seconds: Double) {
    guard isLooping,
      let pointA,
      let pointB
    else { return }

    if seconds >= pointB {
      Task {
        await seek(to: pointA)
      }
    }
  }

  fileprivate func handlePlaybackStateUpdate(_ isPlaying: Bool) {
    self.isPlaying = isPlaying
    updateSleepPrevention()
    sessionTracker?.handlePlaybackStateChanged(isPlaying: isPlaying)

    if isPlaying {
      if let file = currentFile {
        touchPlaybackRecord(for: file)
      }
    }
  }

  func updateSleepPrevention() {
    let shouldPrevent = isPlaying
      && currentFile?.isVideo == true
      && (playerSettings?.preventSleep ?? false)

    if shouldPrevent && sleepActivity == nil {
      sleepActivity = ProcessInfo.processInfo.beginActivity(
        options: [.idleDisplaySleepDisabled, .idleSystemSleepDisabled],
        reason: "Video playback in progress"
      )
    } else if !shouldPrevent, let activity = sleepActivity {
      ProcessInfo.processInfo.endActivity(activity)
      sleepActivity = nil
    }
  }

  fileprivate func handlePlaybackEnded() async {
    if let file = currentFile {
      touchPlaybackRecord(for: file)
      file.playbackRecord?.completionCount += 1
    }

    switch playbackQueue.loopMode {
    case .none:
      isPlaying = false
      updateSleepPrevention()
      sessionTracker?.handlePlaybackStateChanged(isPlaying: false)

    case .repeatOne:
      isPlaying = false
      updateSleepPrevention()
      sessionTracker?.handlePlaybackStateChanged(isPlaying: false)
      await seek(to: 0)
      await play()

    case .repeatAll, .shuffle, .autoPlayNext:
      onPlaybackEnded?(currentFile)
    }
  }

  // MARK: - File Selection

  func selectFile(
    _ file: ABFile,
    fromStart: Bool = false,
    debounce: Bool = true
  ) async {
    playbackQueue.setCurrentFile(file)

    if currentFile?.id == file.id,
      currentFile != nil
    {
      currentFile = file
      return
    }

    sessionTracker?.handlePlaybackStateChanged(isPlaying: false)
    await sessionTracker?.endSessionAndWait()


    loadAudioTask?.cancel()
    if debounce {
      loadAudioTask = Task {
        await clearPlayer()
        if !Task.isCancelled {
          await load(audioFile: file, fromStart: fromStart)
        }
      }
    } else {
      await load(audioFile: file, fromStart: fromStart)
    }
  }

  func playFile(
    _ file: ABFile,
    fromStart: Bool = false
  ) async {
    await selectFile(
      file,
      fromStart: fromStart,
      debounce: false
    )
    await play()
  }

  func playNext() async {
    guard let file = playbackQueue.navigateNext() else {
      return
    }
    let isPlaying = isPlaying
    // TODO: refactor it：always play from start and show a button to restore playing progress
    await selectFile(
      file,
      fromStart: true,
      debounce: false
    )
    if isPlaying {
      await play()
    }
  }

  func playPrev() async {
    guard let file = playbackQueue.navigatePrev() else {
      return
    }
    let isPlaying = isPlaying
    await selectFile(
      file,
      fromStart: true,
      debounce: false
    )
    if isPlaying {
      await play()
    }
  }
}
