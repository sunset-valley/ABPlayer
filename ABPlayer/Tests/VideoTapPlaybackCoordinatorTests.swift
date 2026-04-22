import Foundation
import Testing

@testable import ABPlayerDev

@MainActor
struct VideoTapPlaybackCoordinatorTests {
  @Test
  func singleTapRunsImmediateFeedbackSynchronously() {
    var immediateFeedbackCount = 0
    var delayedActionCount = 0
    let gate = SleepGate()
    let coordinator = VideoTapPlaybackCoordinator(singleTapDelay: .milliseconds(180), sleep: gate.sleep)

    coordinator.handleSingleTap {
      immediateFeedbackCount += 1
    } delayedAction: {
      delayedActionCount += 1
    }

    #expect(immediateFeedbackCount == 1)
    #expect(delayedActionCount == 0)
  }

  @Test
  func singleTapDoesNotRunDelayedActionBeforeDelayCompletes() async {
    var delayedActionCount = 0
    let gate = SleepGate()
    let coordinator = VideoTapPlaybackCoordinator(singleTapDelay: .milliseconds(180), sleep: gate.sleep)

    coordinator.handleSingleTap {} delayedAction: {
      delayedActionCount += 1
    }

    await gate.waitForSleepRequest()
    #expect(delayedActionCount == 0)
  }

  @Test
  func singleTapRunsDelayedActionAfterDelayCompletes() async {
    var delayedActionCount = 0
    let gate = SleepGate()
    let coordinator = VideoTapPlaybackCoordinator(singleTapDelay: .milliseconds(180), sleep: gate.sleep)

    coordinator.handleSingleTap {} delayedAction: {
      delayedActionCount += 1
    }

    await gate.waitForSleepRequest()
    await gate.releaseOne()
    await gate.waitForSettledExecution()

    #expect(delayedActionCount == 1)
  }

  @Test
  func cancelPreventsPendingDelayedAction() async {
    var delayedActionCount = 0
    let gate = SleepGate()
    let coordinator = VideoTapPlaybackCoordinator(singleTapDelay: .milliseconds(180), sleep: gate.sleep)

    coordinator.handleSingleTap {} delayedAction: {
      delayedActionCount += 1
    }

    await gate.waitForSleepRequest()
    coordinator.cancelPendingAction()
    await gate.releaseOne()
    await gate.waitForSettledExecution()

    #expect(delayedActionCount == 0)
  }

  @Test
  func latestSingleTapReplacesOlderPendingAction() async {
    var delayedActionLabels: [String] = []
    let gate = SleepGate()
    let coordinator = VideoTapPlaybackCoordinator(singleTapDelay: .milliseconds(180), sleep: gate.sleep)

    coordinator.handleSingleTap {} delayedAction: {
      delayedActionLabels.append("first")
    }

    await gate.waitForSleepRequest(count: 1)

    coordinator.handleSingleTap {} delayedAction: {
      delayedActionLabels.append("second")
    }

    await gate.waitForSleepRequest(count: 2)
    await gate.releaseOne()
    await gate.waitForSettledExecution()
    #expect(delayedActionLabels.isEmpty)

    await gate.releaseOne()
    await gate.waitForSettledExecution()
    #expect(delayedActionLabels == ["second"])
  }

  @Test
  func invalidateCancelsPendingAction() async {
    var delayedActionCount = 0
    let gate = SleepGate()
    let coordinator = VideoTapPlaybackCoordinator(singleTapDelay: .milliseconds(180), sleep: gate.sleep)

    coordinator.handleSingleTap {} delayedAction: {
      delayedActionCount += 1
    }

    await gate.waitForSleepRequest()
    coordinator.invalidate()
    await gate.releaseOne()
    await gate.waitForSettledExecution()

    #expect(delayedActionCount == 0)
  }
}

actor SleepGate {
  private var requestedCount: Int = 0
  private var continuations: [CheckedContinuation<Void, Never>] = []

  func sleep(_: Duration) async {
    requestedCount += 1
    await withCheckedContinuation { continuation in
      continuations.append(continuation)
    }
  }

  func waitForSleepRequest(count expectedCount: Int = 1) async {
    while requestedCount < expectedCount {
      await Task.yield()
    }
  }

  func releaseOne() {
    guard !continuations.isEmpty else { return }
    let continuation = continuations.removeFirst()
    continuation.resume()
  }

  func waitForSettledExecution() async {
    await Task.yield()
    await Task.yield()
  }
}
