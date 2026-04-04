import XCTest

final class TranscriptScrollUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testTranscriptCanShowFirstAndLastCueAcrossWidthModesWithoutBounceBack() {
    let app = launchApp()
    let compactButton = app.buttons["transcript-scroll-width-compact"]
    let fullButton = app.buttons["transcript-scroll-width-full"]

    XCTAssertTrue(compactButton.waitForExistence(timeout: 4), "Compact width button not found")
    XCTAssertTrue(fullButton.waitForExistence(timeout: 4), "Full width button not found")

    assertTranscriptCanScrollFromFirstToLastWithoutBounceBack(in: app)

    let maxOffsetBeforeCompact = metricDouble(in: app, id: "transcript-scroll-max-offset-y") ?? 0
    compactButton.click()
    XCTAssertTrue(
      waitForMetricChange(
        in: app,
        id: "transcript-scroll-max-offset-y",
        previousValue: maxOffsetBeforeCompact,
        timeout: 4
      ),
      "Compact width did not update scroll metrics"
    )
    assertTranscriptCanScrollFromFirstToLastWithoutBounceBack(in: app)

    let maxOffsetBeforeFull = metricDouble(in: app, id: "transcript-scroll-max-offset-y") ?? 0
    fullButton.click()
    XCTAssertTrue(
      waitForMetricChange(
        in: app,
        id: "transcript-scroll-max-offset-y",
        previousValue: maxOffsetBeforeFull,
        timeout: 4
      ),
      "Full width did not update scroll metrics"
    )
    assertTranscriptCanScrollFromFirstToLastWithoutBounceBack(in: app)
  }

  @MainActor
  private func assertTranscriptCanScrollFromFirstToLastWithoutBounceBack(in app: XCUIApplication) {
    let scrollView = app.scrollViews["transcript-scroll-demo-subtitle-view"]
    XCTAssertTrue(scrollView.waitForExistence(timeout: 6), "Transcript scroll view not found. UI tree:\n\(app.debugDescription)")

    XCTAssertTrue(
      waitForCondition(timeout: 4) {
        self.metricInt(in: app, id: "transcript-scroll-cue-count") ?? 0 > 0
      },
      "Transcript cue count metric did not become available"
    )

    scrollToTop(scrollView: scrollView, app: app)

    let cueCount = metricInt(in: app, id: "transcript-scroll-cue-count") ?? 0
    XCTAssertGreaterThan(cueCount, 1, "Cue count must be greater than 1, got \(cueCount)")

    let firstVisible = metricInt(in: app, id: "transcript-scroll-first-fully-visible-cue-index")
    XCTAssertEqual(
      firstVisible,
      0,
      "Expected first cue to be fully visible at top. metrics=\(metricSnapshot(in: app))"
    )

    let lastCueIndex = cueCount - 1
    let reachedBottom = scrollUntilLastCueFullyVisible(
      scrollView: scrollView,
      app: app,
      lastCueIndex: lastCueIndex,
      maxSwipes: 16
    )
    XCTAssertTrue(
      reachedBottom,
      "Failed to fully reveal last cue after scrolling. metrics=\(metricSnapshot(in: app))"
    )

    let offsetBeforeSettle = metricDouble(in: app, id: "transcript-scroll-offset-y") ?? 0
    XCTAssertTrue(
      waitForCondition(timeout: 0.8) {
        let atBottom = self.metricBool(in: app, id: "transcript-scroll-at-bottom") == true
        let lastVisible = self.metricInt(in: app, id: "transcript-scroll-last-fully-visible-cue-index")
        let offsetNow = self.metricDouble(in: app, id: "transcript-scroll-offset-y") ?? 0
        return atBottom && lastVisible == lastCueIndex && offsetNow >= offsetBeforeSettle - 2
      },
      "Transcript bounced back or lost full visibility at bottom. metrics=\(metricSnapshot(in: app))"
    )
  }

  @MainActor
  private func scrollUntilLastCueFullyVisible(
    scrollView: XCUIElement,
    app: XCUIApplication,
    lastCueIndex: Int,
    maxSwipes: Int
  ) -> Bool {
    for _ in 0 ..< maxSwipes {
      if isAtBottomWithLastCueVisible(in: app, lastCueIndex: lastCueIndex) {
        return true
      }

      scrollView.swipeUp()

      _ = waitForCondition(timeout: 0.25) {
        self.metricBool(in: app, id: "transcript-scroll-at-bottom") == true
          || (self.metricInt(in: app, id: "transcript-scroll-last-fully-visible-cue-index") ?? -1) >= lastCueIndex
      }
    }

    return isAtBottomWithLastCueVisible(in: app, lastCueIndex: lastCueIndex)
  }

  @MainActor
  private func isAtBottomWithLastCueVisible(in app: XCUIApplication, lastCueIndex: Int) -> Bool {
    let atBottom = metricBool(in: app, id: "transcript-scroll-at-bottom") == true
    let lastVisible = metricInt(in: app, id: "transcript-scroll-last-fully-visible-cue-index")
    return atBottom && lastVisible == lastCueIndex
  }

  @MainActor
  private func scrollToTop(scrollView: XCUIElement, app: XCUIApplication) {
    for _ in 0 ..< 12 {
      if metricInt(in: app, id: "transcript-scroll-first-fully-visible-cue-index") == 0 {
        return
      }

      scrollView.swipeDown()
      _ = waitForCondition(timeout: 0.1) {
        self.metricInt(in: app, id: "transcript-scroll-first-fully-visible-cue-index") == 0
      }
    }
  }

  @MainActor
  private func metricText(in app: XCUIApplication, id: String) -> String? {
    let element = app.staticTexts[id]
    guard element.exists else { return nil }

    let raw = (element.value as? String) ?? element.label
    guard let value = raw.split(separator: ":", maxSplits: 1).last else { return nil }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @MainActor
  private func metricDouble(in app: XCUIApplication, id: String) -> Double? {
    guard let text = metricText(in: app, id: id) else { return nil }
    return Double(text)
  }

  @MainActor
  private func metricInt(in app: XCUIApplication, id: String) -> Int? {
    guard let text = metricText(in: app, id: id) else { return nil }
    return Int(text)
  }

  @MainActor
  private func metricBool(in app: XCUIApplication, id: String) -> Bool? {
    guard let text = metricText(in: app, id: id) else { return nil }
    let normalized = text.lowercased()
    if normalized == "true" {
      return true
    }
    if normalized == "false" {
      return false
    }
    return nil
  }

  @MainActor
  private func metricSnapshot(in app: XCUIApplication) -> String {
    let first = metricText(in: app, id: "transcript-scroll-first-fully-visible-cue-index") ?? "nil"
    let last = metricText(in: app, id: "transcript-scroll-last-fully-visible-cue-index") ?? "nil"
    let count = metricText(in: app, id: "transcript-scroll-cue-count") ?? "nil"
    let offset = metricText(in: app, id: "transcript-scroll-offset-y") ?? "nil"
    let maxOffset = metricText(in: app, id: "transcript-scroll-max-offset-y") ?? "nil"
    let atBottom = metricText(in: app, id: "transcript-scroll-at-bottom") ?? "nil"
    return "first=\(first), last=\(last), count=\(count), offset=\(offset), max=\(maxOffset), bottom=\(atBottom)"
  }

  @MainActor
  private func waitForMetricChange(
    in app: XCUIApplication,
    id: String,
    previousValue: Double,
    timeout: TimeInterval
  ) -> Bool {
    waitForCondition(timeout: timeout) {
      guard let current = self.metricDouble(in: app, id: id) else { return false }
      return abs(current - previousValue) > 0.5
    }
  }

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ApplePersistenceIgnoreState", "YES",
      "--ui-testing", "--ui-testing-transcript-scroll",
    ]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_TRANSCRIPT_SCROLL"] = "1"

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)

    let loaded = app.staticTexts["transcript-scroll-demo-title"].waitForExistence(timeout: 20)
    XCTAssertTrue(loaded, "Transcript scroll demo did not load. UI tree:\n\(app.debugDescription)")
    return app
  }

  @MainActor
  private func ensureWindowIsOpen(in app: XCUIApplication) {
    if app.windows.firstMatch.waitForExistence(timeout: 2) {
      return
    }

    app.menuBars.menuBarItems["File"].click()
    let newWindow = app.menuItems["New Window"]
    if newWindow.waitForExistence(timeout: 2) {
      newWindow.click()
    }

    _ = app.windows.firstMatch.waitForExistence(timeout: 5)
  }

  @MainActor
  private func waitForCondition(timeout: TimeInterval, condition: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if condition() {
        return true
      }
      RunLoop.current.run(until: Date().addingTimeInterval(0.05))
    }
    return condition()
  }
}
