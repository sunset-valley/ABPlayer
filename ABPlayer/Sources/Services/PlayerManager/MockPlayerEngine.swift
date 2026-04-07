import AVFoundation
import CoreMedia
import Foundation

actor MockPlayerEngine: PlayerEngineProtocol {
  private var player: AVPlayer?
  private var playbackTask: Task<Void, Never>?
  private var currentTime: Double = 0
  private let duration: Double = 120

  private var onDurationLoaded: (@MainActor @Sendable (Double) -> Void)?
  private var onTimeUpdate: (@MainActor @Sendable (Double) -> Void)?
  private var onLoopCheck: (@MainActor @Sendable (Double) -> Void)?
  private var onPlaybackStateChange: (@MainActor @Sendable (Bool) -> Void)?

  var currentPlayer: AVPlayer? {
    player
  }

  func load(
    fileURL _: URL,
    resumeTime: Double,
    onDurationLoaded: @MainActor @Sendable @escaping (Double) -> Void,
    onTimeUpdate: @MainActor @Sendable @escaping (Double) -> Void,
    onLoopCheck: @MainActor @Sendable @escaping (Double) -> Void,
    onPlaybackStateChange: @MainActor @Sendable @escaping (Bool) -> Void,
    onPlayerReady: @MainActor @Sendable @escaping (AVPlayer) -> Void
  ) async throws -> AVPlayerItem? {
    playbackTask?.cancel()
    playbackTask = nil

    self.onDurationLoaded = onDurationLoaded
    self.onTimeUpdate = onTimeUpdate
    self.onLoopCheck = onLoopCheck
    self.onPlaybackStateChange = onPlaybackStateChange
    currentTime = max(0, resumeTime)

    let player = AVPlayer(playerItem: nil)
    self.player = player

    await onPlayerReady(player)
    await onDurationLoaded(duration)
    await onPlaybackStateChange(false)
    await onTimeUpdate(currentTime)

    return nil
  }

  func play() -> Bool {
    guard player != nil else { return false }

    playbackTask?.cancel()
    playbackTask = Task { [weak self] in
      guard let self else { return }
      await self.setPlaybackState(isPlaying: true)
      await self.runPlaybackTicker()
    }
    return true
  }

  func pause() {
    playbackTask?.cancel()
    playbackTask = nil
    Task { [weak self] in
      await self?.setPlaybackState(isPlaying: false)
    }
  }

  func syncPauseState() {
    playbackTask?.cancel()
    playbackTask = nil
  }

  func syncPlayState() {
    guard playbackTask == nil else { return }
    _ = play()
  }

  func seek(to time: Double) {
    currentTime = min(max(time, 0), duration)
    let time = currentTime
    Task { [weak self] in
      await self?.publishCurrentTime(time)
    }
  }

  func setVolume(_: Float) async {
    // No-op in mock engine.
  }

  func teardown() {
    playbackTask?.cancel()
    playbackTask = nil
    player = nil
    onDurationLoaded = nil
    onTimeUpdate = nil
    onLoopCheck = nil
    onPlaybackStateChange = nil
    currentTime = 0
  }

  private func runPlaybackTicker() async {
    while !Task.isCancelled {
      try? await Task.sleep(nanoseconds: 100_000_000)
      currentTime += 0.1
      if currentTime > duration {
        currentTime = 0
      }
      await publishCurrentTime(currentTime)
    }
  }

  private func publishCurrentTime(_ time: Double) async {
    if let onTimeUpdate {
      await onTimeUpdate(time)
    }
    if let onLoopCheck {
      await onLoopCheck(time)
    }
  }

  private func setPlaybackState(isPlaying: Bool) async {
    if let onPlaybackStateChange {
      await onPlaybackStateChange(isPlaying)
    }
  }
}
