import XCTest

final class VideoSubtitleToggleUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testSubtitleToggleDisabledWhenSubtitleMissing() {
    let app = launchApp()

    let subtitleButton = app.buttons["video-controls-subtitle-toggle"]
    XCTAssertTrue(
      subtitleButton.waitForExistence(timeout: 8),
      "Subtitle toggle button not found. UI tree:\n\(app.debugDescription)"
    )
    XCTAssertTrue(subtitleButton.isEnabled, "Button should be enabled when demo loads with subtitle")

    let noSubtitleButton = app.buttons["video-subtitle-demo-load-without"]
    XCTAssertTrue(noSubtitleButton.waitForExistence(timeout: 4), "Load-without-subtitle button not found")
    noSubtitleButton.click()

    XCTAssertTrue(
      waitForCondition(timeout: 6) { subtitleButton.exists && !subtitleButton.isEnabled },
      "Subtitle button should become disabled for file without subtitle"
    )

    let withSubtitleButton = app.buttons["video-subtitle-demo-load-with"]
    XCTAssertTrue(withSubtitleButton.waitForExistence(timeout: 4), "Load-with-subtitle button not found")
    withSubtitleButton.click()

    XCTAssertTrue(
      waitForCondition(timeout: 6) { subtitleButton.exists && subtitleButton.isEnabled },
      "Subtitle button should become enabled when switching back to subtitle file"
    )
  }

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["--ui-testing", "--ui-testing-video-subtitle-toggle"]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_VIDEO_SUBTITLE_TOGGLE"] = "1"

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)

    let loaded = app.staticTexts["video-subtitle-toggle-demo-title"].waitForExistence(timeout: 20)
    XCTAssertTrue(loaded, "Video subtitle toggle demo did not load. UI tree:\n\(app.debugDescription)")
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
      RunLoop.current.run(until: Date().addingTimeInterval(0.1))
    }
    return condition()
  }
}
