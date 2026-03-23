import XCTest

final class TranscriptScrollUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testTranscriptCanScrollToBottomWithoutBounceBack() {
    let app = launchApp()
    let scrollView = app.scrollViews["transcript-scroll-demo-subtitle-view"]
    XCTAssertTrue(scrollView.waitForExistence(timeout: 6), "Transcript scroll view not found. UI tree:\n\(app.debugDescription)")

    scrollToBottom(scrollView: scrollView)
    let nearBottom = scrollProgress(in: scrollView)

    XCTAssertGreaterThan(
      nearBottom,
      0.90,
      "Transcript did not reach near-bottom progress after scrolling. progress=\(nearBottom)"
    )

    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    let settled = scrollProgress(in: scrollView)

    XCTAssertTrue(
      settled >= nearBottom - 0.05,
      "Transcript bounced back after scroll settled. before=\(nearBottom) after=\(settled)"
    )
  }

  @MainActor
  func testWidthChangeRecomputesScrollableMetrics() {
    let app = launchApp()
    let scrollView = app.scrollViews["transcript-scroll-demo-subtitle-view"]
    let compactButton = app.buttons["transcript-scroll-width-compact"]
    let fullButton = app.buttons["transcript-scroll-width-full"]

    XCTAssertTrue(scrollView.waitForExistence(timeout: 6), "Demo transcript scroll view not found")
    XCTAssertTrue(compactButton.waitForExistence(timeout: 4), "Compact width button not found")
    XCTAssertTrue(fullButton.waitForExistence(timeout: 4), "Full width button not found")

    scrollToTop(scrollView: scrollView)
    compactButton.click()
    waitForLayoutSettle()
    scrollBySteps(scrollView: scrollView, steps: 6)
    let compactProgress = scrollProgress(in: scrollView)

    fullButton.click()
    waitForLayoutSettle()
    scrollToTop(scrollView: scrollView)
    scrollBySteps(scrollView: scrollView, steps: 6)
    let fullProgress = scrollProgress(in: scrollView)

    XCTAssertGreaterThan(
      fullProgress,
      compactProgress + 0.1,
      "Compact width did not increase effective scroll range. compact=\(compactProgress) full=\(fullProgress)"
    )
  }

  @MainActor
  private func waitForLayoutSettle() {
    RunLoop.current.run(until: Date().addingTimeInterval(0.25))
  }

  @MainActor
  private func scrollBySteps(scrollView: XCUIElement, steps: Int) {
    for _ in 0 ..< steps {
      scrollView.swipeUp()
    }
  }

  @MainActor
  private func scrollToTop(scrollView: XCUIElement) {
    for _ in 0 ..< 12 {
      scrollView.swipeDown()
    }
  }

  @MainActor
  private func scrollProgress(in scrollView: XCUIElement) -> Double {
    let indicator = scrollView.scrollBars.firstMatch.value
    if let value = indicator as? String,
       let number = Double(value)
    {
      return number
    }

    if let value = indicator as? NSNumber {
      return value.doubleValue
    }

    return 0
  }

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["--ui-testing", "--ui-testing-transcript-scroll"]
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
  private func scrollToBottom(scrollView: XCUIElement) {
    for _ in 0 ..< 24 {
      scrollView.swipeUp()
    }
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
}
