import XCTest

final class TranscriptionUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testEmptyStateShowsUnifiedPrimaryAction() {
    let app = launchApp(state: "empty")

    let stateView = element(in: app, id: "transcription-state-view")
    XCTAssertTrue(stateView.waitForExistence(timeout: 6), "State container not found. UI tree:\n\(app.debugDescription)")

    XCTAssertTrue(title(in: app, value: "No Transcription").exists)
    XCTAssertTrue(button(in: app, label: "Transcribe Audio").exists)
    XCTAssertFalse(button(in: app, label: "Cancel").exists)
  }

  @MainActor
  func testDownloadingStateShowsProgressAndInlineCancelButton() {
    let app = launchApp(state: "downloading")
    assertUnifiedStateScaffold(in: app, expectedTitle: "Downloading Model")

    XCTAssertGreaterThan(progressIndicatorCount(in: app), 0, "Progress indicator missing in downloading state")

    let cancel = button(in: app, label: "Cancel")
    XCTAssertTrue(cancel.waitForExistence(timeout: 4), "Cancel button missing in downloading state")
    assertActionIsInline(button: cancel, in: app)
  }

  @MainActor
  func testLoadingModelStateUsesUnifiedStateContainer() {
    let app = launchApp(state: "loading-model")
    assertUnifiedStateScaffold(in: app, expectedTitle: "Loading Model")

    XCTAssertTrue(
      title(in: app, value: "This may take a moment on first run").exists,
      "Footnote missing in loading-model state"
    )
  }

  @MainActor
  func testFailedStateShowsRetryActionInUnifiedLayout() {
    let app = launchApp(state: "failed")
    assertUnifiedStateScaffold(in: app, expectedTitle: "Transcription Failed")

    let retry = button(in: app, label: "Try Again")
    XCTAssertTrue(retry.waitForExistence(timeout: 4), "Retry button missing in failed state")
    assertActionIsInline(button: retry, in: app)
  }

  @MainActor
  func testContentStateShowsToolbarAndSubtitleContent() {
    let app = launchApp(state: "content")

    let retranscribe = button(in: app, label: "Re-transcribe")
    XCTAssertTrue(retranscribe.waitForExistence(timeout: 6), "Re-transcribe button missing. UI tree:\n\(app.debugDescription)")

    XCTAssertTrue(button(in: app, label: "Small").exists)
    XCTAssertTrue(button(in: app, label: "Medium").exists)
    XCTAssertTrue(button(in: app, label: "Large").exists)
  }

  @MainActor
  func testQueuedStateUsesUnifiedContainer() {
    let app = launchApp(state: "queued")
    assertUnifiedStateScaffold(in: app, expectedTitle: "Queued")

    XCTAssertTrue(title(in: app, value: "Waiting for other transcriptions to complete").exists)
    XCTAssertFalse(button(in: app, label: "Cancel").exists)
  }

  @MainActor
  func testQueueDownloadingStateShowsInlineCancelButton() {
    let app = launchApp(state: "queue-downloading")
    assertUnifiedStateScaffold(in: app, expectedTitle: "Downloading Model")

    let cancel = button(in: app, label: "Cancel")
    XCTAssertTrue(cancel.waitForExistence(timeout: 4), "Cancel button missing in queue-downloading state")
    assertActionIsInline(button: cancel, in: app)
  }

  @MainActor
  func testQueueFailedStateShowsInlineRemoveButton() {
    let app = launchApp(state: "queue-failed")
    assertUnifiedStateScaffold(in: app, expectedTitle: "Transcription Failed")

    let remove = button(in: app, label: "Remove")
    XCTAssertTrue(remove.waitForExistence(timeout: 4), "Remove button missing in queue-failed state")
    assertActionIsInline(button: remove, in: app)
  }

  @MainActor
  private func launchApp(state: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ApplePersistenceIgnoreState", "YES",
      "--ui-testing", "--ui-testing-transcription",
      "--ui-testing-transcription-state", state,
    ]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_TRANSCRIPTION"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_TRANSCRIPTION_STATE"] = state

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)

    let loaded = app.staticTexts["transcription-demo-title"].waitForExistence(timeout: 20)
    XCTAssertTrue(loaded, "Transcription demo did not load. UI tree:\n\(app.debugDescription)")
    return app
  }

  @MainActor
  private func assertUnifiedStateScaffold(in app: XCUIApplication, expectedTitle: String) {
    let stateView = element(in: app, id: "transcription-state-view")
    XCTAssertTrue(stateView.waitForExistence(timeout: 6), "State container missing. UI tree:\n\(app.debugDescription)")

    XCTAssertTrue(title(in: app, value: expectedTitle).exists)
  }

  @MainActor
  private func assertActionIsInline(button: XCUIElement, in app: XCUIApplication) {
    let stateView = element(in: app, id: "transcription-state-view")
    let progress = app.windows.firstMatch.progressIndicators.firstMatch

    XCTAssertTrue(stateView.exists)
    XCTAssertTrue(button.exists)

    XCTAssertTrue(
      waitForCondition(timeout: 3) {
        stateView.frame.width > 0 && button.frame.width > 0
      },
      "State/action frames are not ready"
    )

    let buttonFrame = button.frame
    let windowFrame = app.windows.firstMatch.frame

    XCTAssertGreaterThan(buttonFrame.minY, windowFrame.minY + 180, "Action button should be below header block")

    if progress.exists {
      XCTAssertGreaterThan(
        buttonFrame.minY,
        progress.frame.maxY,
        "Action button should appear below progress section"
      )
    }

    let distanceFromBottom = windowFrame.maxY - buttonFrame.maxY
    XCTAssertGreaterThan(
      distanceFromBottom,
      100,
      "Action button should not be pinned to window bottom"
    )
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

  @MainActor
  private func element(in app: XCUIApplication, id: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: id).firstMatch
  }

  @MainActor
  private func title(in app: XCUIApplication, value: String) -> XCUIElement {
    app.windows.firstMatch.staticTexts.matching(
      NSPredicate(format: "label == %@ OR value == %@", value, value)
    ).firstMatch
  }

  @MainActor
  private func button(in app: XCUIApplication, label: String) -> XCUIElement {
    app.windows.firstMatch.descendants(matching: .button).matching(
      NSPredicate(format: "label == %@", label)
    ).firstMatch
  }

  @MainActor
  private func progressIndicatorCount(in app: XCUIApplication) -> Int {
    app.windows.firstMatch.progressIndicators.count
  }
}
