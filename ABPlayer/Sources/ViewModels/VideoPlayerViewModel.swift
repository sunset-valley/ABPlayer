import Foundation
import Observation
import SwiftUI

@Observable
@MainActor
final class VideoPlayerViewModel: BasePlayerViewModel {
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
      try? await Task.sleep(nanoseconds: 10_000_000)
      guard !Task.isCancelled else { return }

      withAnimation(.bouncy(duration: 0.25)) {
        isHudVisible = true
      }

      try? await Task.sleep(nanoseconds: 2_500_000_000)
      guard !Task.isCancelled else { return }

      withAnimation(.bouncy(duration: 0.25)) {
        isHudVisible = false
      }

      try? await Task.sleep(nanoseconds: 250_000_000)
      guard !Task.isCancelled else { return }

      hudMessage = nil
    }
  }
}
