import XCTest

final class VideoTapPlaybackUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testSingleClickShowsImmediateFeedbackAndEventuallyTogglesPlayback() {
    let app = launchApp()

    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 8), "App window not found. UI tree:\n\(app.debugDescription)")

    let initialPlaybackState = metricText(in: app, id: "video-tap-playback-state")
    XCTAssertNotNil(initialPlaybackState, "Playback state label not found")

    videoSurfaceCoordinate(in: app).click()

    XCTAssertTrue(
      waitForCondition(timeout: 1.5) { self.metricInt(in: app, id: "video-tap-feedback-count") == 1 },
      "Immediate feedback count did not increment after single click"
    )

    XCTAssertTrue(
      waitForCondition(timeout: 2.5) {
        self.metricText(in: app, id: "video-tap-playback-state") != initialPlaybackState
      },
      "Playback state did not toggle after delayed single click"
    )
  }

  @MainActor
  func testDoubleClickTogglesFullscreenWithoutPlaybackToggle() {
    let app = launchApp()

    let window = app.windows.firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: 8), "App window not found. UI tree:\n\(app.debugDescription)")

    let initialPlaybackState = metricText(in: app, id: "video-tap-playback-state")
    XCTAssertEqual(metricText(in: app, id: "video-tap-fullscreen-state"), "dismissed")

    videoSurfaceCoordinate(in: app).doubleClick()

    XCTAssertTrue(
      waitForCondition(timeout: 2.5) {
        self.metricText(in: app, id: "video-tap-fullscreen-state") == "presented"
      },
      "Fullscreen state did not switch to presented after double click"
    )

    XCTAssertTrue(
      waitForCondition(timeout: 1.5) { self.metricInt(in: app, id: "video-tap-feedback-count") == 1 },
      "First click of double click should still increment feedback count"
    )

    RunLoop.current.run(until: Date().addingTimeInterval(0.4))
    XCTAssertEqual(
      metricText(in: app, id: "video-tap-playback-state"),
      initialPlaybackState,
      "Playback state should not toggle during fullscreen double click"
    )
  }

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ApplePersistenceIgnoreState", "YES",
      "--ui-testing", "--ui-testing-video-tap-playback",
    ]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_VIDEO_TAP_PLAYBACK"] = "1"

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)

    let loaded = app.staticTexts["video-tap-demo-title"].waitForExistence(timeout: 20)
    XCTAssertTrue(loaded, "Video tap demo did not load. UI tree:\n\(app.debugDescription)")
    return app
  }

  @MainActor
  private func videoSurfaceCoordinate(in app: XCUIApplication) -> XCUICoordinate {
    app.windows.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35))
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
  private func metricInt(in app: XCUIApplication, id: String) -> Int? {
    guard let text = metricText(in: app, id: id) else { return nil }
    return Int(text)
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
