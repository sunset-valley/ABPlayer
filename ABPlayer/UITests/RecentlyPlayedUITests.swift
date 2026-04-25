import XCTest

final class RecentlyPlayedUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testCurrentFolderCardSwitchesTo84AndShowsNowPlayingWithoutProgress() {
    let app = launchApp()

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-setup-state", expected: "done", timeout: 10),
      "Recently played demo setup did not complete in time. UI tree:\n\(app.debugDescription)"
    )

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-card-file", expected: "83_9", timeout: 8),
      "Initial card file metric did not reach 83_9. UI tree:\n\(app.debugDescription)"
    )

    let playButton = app.buttons["recently-played-demo-play-84_10"]
    XCTAssertTrue(playButton.waitForExistence(timeout: 4), "Play 84_10 button not found. UI tree:\n\(app.debugDescription)")
    playButton.click()

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-card-file", expected: "84_10", timeout: 8),
      "Card file metric did not switch to 84_10"
    )

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-card-now-playing", expected: "true", timeout: 8),
      "Card now-playing metric did not become true"
    )
    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-card-progress-visible", expected: "false", timeout: 8),
      "Card progress visibility metric did not become false"
    )
  }

  @MainActor
  func testGlobalRecentRowShowsNowPlayingWithoutProgress() {
    let app = launchApp()

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-setup-state", expected: "done", timeout: 10),
      "Recently played demo setup did not complete in time. UI tree:\n\(app.debugDescription)"
    )

    let playButton = app.buttons["recently-played-demo-play-84_10"]
    XCTAssertTrue(playButton.waitForExistence(timeout: 4), "Play 84_10 button not found. UI tree:\n\(app.debugDescription)")
    playButton.click()

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-card-file", expected: "84_10", timeout: 8),
      "Current-folder card metric did not reach 84_10 before global assertions"
    )

    let menuButton = app.buttons["recently-played-menu-button"]
    XCTAssertTrue(menuButton.waitForExistence(timeout: 4), "Recently played menu button not found. UI tree:\n\(app.debugDescription)")
    menuButton.click()

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-popover-presented", expected: "true", timeout: 4),
      "Popover presentation state did not become true after first click. UI tree:\n\(app.debugDescription)"
    )

    RunLoop.current.run(until: Date().addingTimeInterval(0.6))
    XCTAssertEqual(
      metricText(in: app, id: "recently-played-metric-popover-presented"),
      "true",
      "Recently played popover state did not remain true after first click. UI tree:\n\(app.debugDescription)"
    )

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-global-84-now-playing", expected: "true", timeout: 8),
      "Global 84_10 now-playing metric did not become true"
    )
    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-global-84-progress-visible", expected: "false", timeout: 8),
      "Global 84_10 progress visibility metric did not become false"
    )
  }

  @MainActor
  func testGlobalRecentPopoverShowsFiveSkeletonRowsWhileLoading() {
    let app = launchApp(extraLaunchArguments: ["--ui-testing-recently-played-loading"]) 

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-setup-state", expected: "done", timeout: 10),
      "Recently played demo setup did not complete in time. UI tree:\n\(app.debugDescription)"
    )

    let menuButton = app.buttons["recently-played-menu-button"]
    XCTAssertTrue(menuButton.waitForExistence(timeout: 4), "Recently played menu button not found. UI tree:\n\(app.debugDescription)")
    menuButton.click()

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-popover-presented", expected: "true", timeout: 4),
      "Popover presentation state did not become true after first click. UI tree:\n\(app.debugDescription)"
    )

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-popover-loading-seen", expected: "true", timeout: 4),
      "Popover loading phase was not observed on first open. UI tree:\n\(app.debugDescription)"
    )

    XCTAssertEqual(
      metricText(in: app, id: "recently-played-metric-popover-loading-seen"),
      "true",
      "Popover loading observed flag did not remain true during first open. UI tree:\n\(app.debugDescription)"
    )

    XCTAssertTrue(
      waitForMetricValue(in: app, id: "recently-played-metric-popover-loading", expected: "false", timeout: 8),
      "Popover loading state did not clear after skeleton phase. UI tree:\n\(app.debugDescription)"
    )

    XCTAssertEqual(
      metricText(in: app, id: "recently-played-metric-popover-presented"),
      "true",
      "Popover should remain presented after loading completes. UI tree:\n\(app.debugDescription)"
    )
  }

  @MainActor
  private func launchApp(extraLaunchArguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ApplePersistenceIgnoreState", "YES",
      "--ui-testing", "--ui-testing-recently-played",
    ]
    app.launchArguments += extraLaunchArguments
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_RECENTLY_PLAYED"] = "1"

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)

    let loaded = app.staticTexts["recently-played-demo-title"].waitForExistence(timeout: 20)
    XCTAssertTrue(loaded, "Recently played demo did not load. UI tree:\n\(app.debugDescription)")
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
  private func metricText(in app: XCUIApplication, id: String) -> String? {
    let element = app.staticTexts[id]
    guard element.waitForExistence(timeout: 1) else { return nil }

    let raw = (element.value as? String) ?? element.label
    guard let value = raw.split(separator: ":", maxSplits: 1).last else { return nil }
    return value.trimmingCharacters(in: .whitespacesAndNewlines)
  }

  @MainActor
  private func waitForMetricValue(
    in app: XCUIApplication,
    id: String,
    expected: String,
    timeout: TimeInterval
  ) -> Bool {
    waitForCondition(timeout: timeout) {
      self.metricText(in: app, id: id) == expected
    }
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
