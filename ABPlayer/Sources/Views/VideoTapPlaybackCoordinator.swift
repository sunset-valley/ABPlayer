import Foundation

@MainActor
final class VideoTapPlaybackCoordinator {
  typealias Sleep = @Sendable (_ duration: Duration) async -> Void

  private let singleTapDelay: Duration
  private let sleep: Sleep

  private var pendingSingleTapTask: Task<Void, Never>?

  init(
    singleTapDelay: Duration = .milliseconds(180),
    sleep: @escaping Sleep = { duration in
      try? await Task.sleep(for: duration)
    }
  ) {
    self.singleTapDelay = singleTapDelay
    self.sleep = sleep
  }

  func handleSingleTap(
    immediateFeedback: @escaping @MainActor () -> Void,
    delayedAction: @escaping @MainActor () -> Void
  ) {
    cancelPendingAction()
    immediateFeedback()

    let delay = singleTapDelay
    let sleep = self.sleep

    pendingSingleTapTask = Task { @MainActor [weak self] in
      await sleep(delay)
      guard !Task.isCancelled else { return }

      delayedAction()
      self?.pendingSingleTapTask = nil
    }
  }

  @discardableResult
  func cancelPendingAction() -> Bool {
    let hadPendingAction = pendingSingleTapTask != nil
    pendingSingleTapTask?.cancel()
    pendingSingleTapTask = nil
    return hadPendingAction
  }

  func invalidate() {
    cancelPendingAction()
  }
}
