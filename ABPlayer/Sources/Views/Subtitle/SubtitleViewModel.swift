import Foundation
import OSLog

@Observable
@MainActor
final class SubtitleViewModel {
  private static let logger = Logger(subsystem: "com.abplayer", category: "SubtitleViewModel")

  // MARK: - Types

  // MARK: - Output

  struct Output: Equatable {
    let currentCueID: UUID?
    let scrollState: ScrollState
    let textSelection: TextSelectionState
  }

  enum ScrollState: Equatable {
    case autoScrolling
    case userScrolling

    var isUserScrolling: Bool {
      self == .userScrolling
    }
  }

  enum TextSelectionState: Equatable {
    case none
    /// User has selected (possibly cross-cue) text.
    case selecting(selection: CrossCueTextSelection)
    /// User has tapped an existing annotation.
    case annotationSelected(groupID: UUID, selection: CrossCueTextSelection)

    // MARK: Convenience accessors

    var isActive: Bool { self != .none }
  }

  // MARK: - Dependencies

  @ObservationIgnored
  private(set) weak var playerManager: PlayerManager?

  // MARK: - UI State

  private(set) var currentCueID: UUID?
  private(set) var scrollState: ScrollState = .autoScrolling
  private(set) var textSelection: TextSelectionState = .none

  var output: Output { makeOutput() }

  // MARK: - Internal State

  private var wasPlayingBeforeSelection = false

  // MARK: - Observation

  @ObservationIgnored
  private var playbackObserverID: UUID?

  // MARK: - Initialization

  init(playerManager: PlayerManager? = nil) {
    self.playerManager = playerManager
  }

  // MARK: - Public API

  func setPlayerManager(_ playerManager: PlayerManager) {
    self.playerManager = playerManager
  }

  @MainActor
  func handleUserScroll() {
    scrollState = .userScrolling
  }

  func cancelScrollResume() {
    scrollState = .autoScrolling
  }

  func handleTextSelection(
    selection: CrossCueTextSelection?,
    isPlaying: Bool,
    onPause: () -> Void,
    onPlay: () -> Void
  ) {
    if let selection {
      pausePlaybackForSelectionIfNeeded(isPlaying: isPlaying, onPause: onPause)
      textSelection = .selecting(selection: selection)
      Self.logger.debug(
        "Selected '\(selection.fullText.prefix(40))' across \(selection.segments.count) cue(s)")
    } else {
      dismissSelection(onPlay: onPlay)
    }
  }

  func selectAnnotation(groupID: UUID, selection: CrossCueTextSelection, isPlaying: Bool, onPause: () -> Void) {
    pausePlaybackForSelectionIfNeeded(isPlaying: isPlaying, onPause: onPause)
    textSelection = .annotationSelected(groupID: groupID, selection: selection)
  }

  func dismissSelection(onPlay: () -> Void) {
    guard textSelection != .none else { return }
    textSelection = .none
    if wasPlayingBeforeSelection {
      onPlay()
      wasPlayingBeforeSelection = false
    }
  }

  @MainActor
  func handleCueTap(cueID: UUID, cueStartTime: Double) async {
    assert(cueStartTime >= 0, "Cue start time must be non-negative")
    assert(cueStartTime.isFinite, "Cue start time must be finite")

    await playerManager?.seek(to: cueStartTime + 0.001)
    currentCueID = cueID
    scrollState = .autoScrolling
    Self.logger.debug("Tapped cue at time \(cueStartTime)")
  }

  func updateCurrentCue(time: Double, cues: [SubtitleCue]) {
    assert(time >= 0, "Time must be non-negative")
    assert(time.isFinite, "Time must be finite")

    guard !scrollState.isUserScrolling else { return }
    currentCueID = cues.latestStartedCue(at: time)?.id
  }

  @MainActor
  func reset() {
    stopTrackingPlayback()
    currentCueID = nil
    scrollState = .autoScrolling
    textSelection = .none
    wasPlayingBeforeSelection = false
  }

  @MainActor
  func trackPlayback(cues: [SubtitleCue]) async {
    let epsilon = 0.001
    stopTrackingPlayback()

    guard !cues.isEmpty else {
      Self.logger.warning("trackPlayback called with empty cues array")
      currentCueID = nil
      return
    }

    guard let playerManager else {
      Self.logger.warning("trackPlayback called without playerManager")
      currentCueID = nil
      return
    }

    playbackObserverID = playerManager.addPlaybackTimeObserver { [weak self] currentTime in
      guard let self else { return }
      guard currentTime.isFinite, currentTime >= 0 else {
        Self.logger.error("Invalid playback time from PlayerManager: \(currentTime)")
        return
      }

      self.trackCurrentCue(at: currentTime, in: cues, epsilon: epsilon)
    }

    Self.logger.debug("Started tracking playback for \(cues.count) cues")
    do {
      try await Task.sleep(nanoseconds: UInt64.max)
    } catch {
      Self.logger.debug("Playback tracking cancelled: \(error.localizedDescription)")
    }
  }

  @MainActor
  func stopTrackingPlayback() {
    if let playbackObserverID {
      playerManager?.removePlaybackTimeObserver(playbackObserverID)
    }
    playbackObserverID = nil
  }

  // MARK: - Private

  private func makeOutput() -> Output {
    Output(
      currentCueID: currentCueID,
      scrollState: scrollState,
      textSelection: textSelection
    )
  }

  private func pausePlaybackForSelectionIfNeeded(isPlaying: Bool, onPause: () -> Void) {
    guard textSelection == .none else { return }

    wasPlayingBeforeSelection = isPlaying
    if isPlaying {
      onPause()
    }
  }

  private func trackCurrentCue(at currentTime: Double, in cues: [SubtitleCue], epsilon: Double) {
    guard !scrollState.isUserScrolling else { return }

    let latestStartedCue = cues.latestStartedCue(at: currentTime, epsilon: epsilon)
    if latestStartedCue?.id != currentCueID {
      currentCueID = latestStartedCue?.id
      if let cue = latestStartedCue {
        Self.logger.debug("Latest started cue changed: \(cue.text.prefix(30))...")
      }
    }
  }

}
