import Observation

@MainActor
@Observable
final class VideoTapInteractionMonitor {
  private(set) var immediateFeedbackCount: Int = 0
  private(set) var isFullscreenPresented: Bool = false

  func recordImmediateFeedback() {
    immediateFeedbackCount += 1
  }

  func setFullscreenPresented(_ isPresented: Bool) {
    isFullscreenPresented = isPresented
  }
}
