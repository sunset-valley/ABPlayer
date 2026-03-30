import XCTest

final class SubtitlePlaybackAnnotationUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testPlaybackKeepsAdvancingAfterAnnotateAndDismiss() {
    let app = launchApp()

    let activeCueLabel = app.staticTexts["subtitle-playback-active-cue"]
    XCTAssertTrue(
      activeCueLabel.waitForExistence(timeout: 6),
      "Active cue label not found. UI tree:\n\(app.debugDescription)"
    )

    let initialCueIndex = waitForActiveCueIndex(in: app, timeout: 6)
    XCTAssertNotNil(initialCueIndex, "Expected active cue to become available before selection")

    let applyAnnotationButton = app.buttons["subtitle-playback-apply-annotation"]
    XCTAssertTrue(
      applyAnnotationButton.waitForExistence(timeout: 4),
      "Apply annotation action not found. UI tree:\n\(app.debugDescription)"
    )
    applyAnnotationButton.click()

    XCTAssertTrue(
      waitForCondition(timeout: 4) { app.staticTexts["subtitle-playback-following"].exists },
      "Following state label should stay available after apply/resume"
    )

    let followingLabel = app.staticTexts["subtitle-playback-following"]
    XCTAssertTrue(followingLabel.waitForExistence(timeout: 2), "Following state label not found")

    XCTAssertTrue(
      waitForCondition(timeout: 6) {
        guard let nextCueIndex = self.activeCueIndex(in: app),
          let initialCueIndex
        else { return false }
        return nextCueIndex > initialCueIndex
      },
      "Active cue did not advance after annotation dismiss. active=\((activeCueLabel.value as? String) ?? activeCueLabel.label)"
    )

    XCTAssertTrue(
      waitForCondition(timeout: 6) {
        let followingValue = (followingLabel.value as? String) ?? followingLabel.label
        return followingValue.contains("true")
      },
      "Playback should eventually return to following state after dismiss, got: \((followingLabel.value as? String) ?? followingLabel.label)"
    )

    let followButton = app.buttons["subtitle-follow-playback-button"]
    XCTAssertFalse(
      followButton.exists,
      "Follow-playback button should be hidden before manual scroll"
    )

    let transcriptScrollView = transcriptScrollViewElement(in: app)
    XCTAssertTrue(
      transcriptScrollView.waitForExistence(timeout: 4),
      "Transcript scroll view not found for follow-button transition test"
    )
    transcriptScrollView.swipeUp()

    XCTAssertTrue(
      waitForCondition(timeout: 4) { followButton.exists },
      "Follow-playback button should appear after manual scrolling"
    )

    if followButton.isHittable {
      followButton.click()
    } else {
      followButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
    }

    XCTAssertTrue(
      waitForCondition(timeout: 4) { !followButton.exists },
      "Follow-playback button should hide after resuming follow"
    )
  }

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ApplePersistenceIgnoreState", "YES",
      "--ui-testing",
      "--ui-testing-subtitle-playback-annotation",
    ]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_SUBTITLE_PLAYBACK_ANNOTATION"] = "1"

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)

    let loaded = app.staticTexts["subtitle-playback-annotation-demo-title"].waitForExistence(timeout: 20)
    XCTAssertTrue(loaded, "Subtitle playback annotation demo did not load. UI tree:\n\(app.debugDescription)")

    return app
  }

  @MainActor
  private func transcriptScrollViewElement(in app: XCUIApplication) -> XCUIElement {
    let transcriptScrollView = app.scrollViews["subtitle-transcript-scroll-view"]
    if transcriptScrollView.exists {
      return transcriptScrollView
    }

    return app.scrollViews["subtitle-playback-annotation-demo-subtitle-view"]
  }

  @MainActor
  private func waitForActiveCueIndex(in app: XCUIApplication, timeout: TimeInterval) -> Int? {
    var value: Int?
    _ = waitForCondition(timeout: timeout) {
      if let active = self.activeCueIndex(in: app) {
        value = active
        return true
      }
      return false
    }
    return value
  }

  @MainActor
  private func activeCueIndex(in app: XCUIApplication) -> Int? {
    let element = app.staticTexts["subtitle-playback-active-cue"]
    guard element.exists else { return nil }
    let rawValue = (element.value as? String) ?? element.label
    guard let suffix = rawValue.split(separator: ":").last else { return nil }
    let trimmed = suffix.trimmingCharacters(in: .whitespacesAndNewlines)
    return Int(trimmed)
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
