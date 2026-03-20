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
}
