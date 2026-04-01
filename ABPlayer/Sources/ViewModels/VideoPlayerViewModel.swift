import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class VideoPlayerViewModel: BasePlayerViewModel {
  private let hudShowDelay: Duration = .milliseconds(10)
  private let hudVisibleDuration: Duration = .milliseconds(2500)
  private let hudCleanupDelay: Duration = .milliseconds(250)

  // MARK: - HUD
  var hudMessage: String?
  var isHudVisible: Bool = false
  var hideHudTask: Task<Void, Never>?

  // MARK: - Subtitles

  var isSubtitleEnabled: Bool = false
  private(set) var subtitleCues: [SubtitleCue] = []
  private(set) var currentSubtitleText: String?

  @ObservationIgnored
  private var subtitlePlaybackObserverID: UUID?

  var hasAvailableSubtitles: Bool {
    !subtitleCues.isEmpty
  }

  override func setup(with manager: PlayerManager) {
    super.setup(with: manager)
    startSubtitleTrackingIfNeeded(using: manager)
  }

  // MARK: - Seek overrides (add HUD feedback)

  override func seekBack() {
    super.seekBack()
    showHUDMessage("- 5")
  }

  override func seekForward() {
    super.seekForward()
    showHUDMessage("+ 10s")
  }

  // MARK: - HUD

  func showHUDMessage(_ message: String) {
    hideHudTask?.cancel()

    hudMessage = message
    isHudVisible = false

    hideHudTask = Task { @MainActor in
      try? await Task.sleep(for: hudShowDelay)
      guard !Task.isCancelled else { return }

      setHUDVisibility(true)

      try? await Task.sleep(for: hudVisibleDuration)
      guard !Task.isCancelled else { return }

      setHUDVisibility(false)

      try? await Task.sleep(for: hudCleanupDelay)
      guard !Task.isCancelled else { return }

      hudMessage = nil
    }
  }

  private func setHUDVisibility(_ isVisible: Bool) {
    withAnimation(.bouncy(duration: 0.25)) {
      isHudVisible = isVisible
    }
  }

  func updateSubtitleCues(_ cues: [SubtitleCue]) {
    assert(
      cues.isEmpty || zip(cues, cues.dropFirst()).allSatisfy({ $0.startTime <= $1.startTime }),
      "subtitleCues must be sorted by startTime for binary search"
    )
    subtitleCues = cues

    guard hasAvailableSubtitles, isSubtitleEnabled else {
      currentSubtitleText = nil
      return
    }

    let playbackTime = playerManager?.currentTime ?? 0
    updateCurrentSubtitle(at: playbackTime)
  }

  func toggleSubtitle() {
    guard hasAvailableSubtitles else { return }

    isSubtitleEnabled.toggle()
    if !isSubtitleEnabled {
      currentSubtitleText = nil
      return
    }

    let playbackTime = playerManager?.currentTime ?? 0
    updateCurrentSubtitle(at: playbackTime)
  }

  /// Clears cues and current subtitle text while preserving `isSubtitleEnabled`,
  /// so the user's preference is restored once new cues arrive via `updateSubtitleCues`.
  func beginSubtitleReload() {
    subtitleCues = []
    currentSubtitleText = nil
  }

  func loadSubtitles(for audioFile: ABFile, using subtitleLoader: SubtitleLoader) async {
    let cues = await subtitleLoader.loadSubtitles(for: audioFile)
    updateSubtitleCues(cues)
  }

  func refreshSubtitles(for audioFileID: UUID, using subtitleLoader: SubtitleLoader) {
    updateSubtitleCues(subtitleLoader.cachedSubtitles(for: audioFileID))
  }

  func updateCurrentSubtitle(at time: Double) {
    guard isSubtitleEnabled, hasAvailableSubtitles else {
      currentSubtitleText = nil
      return
    }

    currentSubtitleText = subtitleCues.findActiveCue(at: time)?.text
  }

  private func startSubtitleTrackingIfNeeded(using manager: PlayerManager) {
    guard subtitlePlaybackObserverID == nil else { return }

    subtitlePlaybackObserverID = manager.addPlaybackTimeObserver { [weak self] currentTime in
      self?.updateCurrentSubtitle(at: currentTime)
    }
  }

  func stopSubtitleTracking() {
    guard let subtitlePlaybackObserverID else { return }
    playerManager?.removePlaybackTimeObserver(subtitlePlaybackObserverID)
    self.subtitlePlaybackObserverID = nil
  }

}
