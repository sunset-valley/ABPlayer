import XCTest

final class SubtitleEditUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testEditSubtitleFromContextMenuPersistsInView() {
    let app = launchApp()

    let transcript = transcriptInteractionElement(in: app)
    XCTAssertTrue(
      transcript.waitForExistence(timeout: 6),
      "Transcript view not found. UI tree:\n\(app.debugDescription)"
    )

    let clickPoint = transcript.coordinate(withNormalizedOffset: CGVector(dx: 0.22, dy: 0.22))
    clickPoint.rightClick()

    let editMenuItem = app.menuItems["Edit Subtitle"]
    XCTAssertTrue(
      editMenuItem.waitForExistence(timeout: 3),
      "Edit Subtitle menu item not found. UI tree:\n\(app.debugDescription)"
    )
    editMenuItem.click()

    let editor = app.textViews["subtitle-edit-text-editor"]
    XCTAssertTrue(
      editor.waitForExistence(timeout: 4),
      "Subtitle editor did not appear. UI tree:\n\(app.debugDescription)"
    )

    replaceText(in: editor, with: "Edited by UI test")

    let confirmButton = app.buttons["subtitle-edit-confirm"]
    XCTAssertTrue(confirmButton.waitForExistence(timeout: 2), "Confirm button not found")
    XCTAssertTrue(confirmButton.isEnabled, "Confirm button should be enabled after editing")
    confirmButton.click()

    XCTAssertFalse(editor.waitForExistence(timeout: 3), "Editor sheet did not close after confirm")

    let updatedText = app.staticTexts["subtitle-edit-demo-current-text"]
    XCTAssertTrue(updatedText.waitForExistence(timeout: 4), "Updated text label not found")
    let displayedText = (updatedText.value as? String) ?? updatedText.label
    XCTAssertEqual(displayedText, "Edited by UI test")
  }

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["--ui-testing", "--ui-testing-subtitle-edit"]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_SUBTITLE_EDIT"] = "1"

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)

    let loaded = app.staticTexts["subtitle-edit-demo-title"].waitForExistence(timeout: 20)
    XCTAssertTrue(loaded, "Subtitle edit demo view did not load. UI tree:\n\(app.debugDescription)")

    return app
  }

  @MainActor
  private func replaceText(in textView: XCUIElement, with value: String) {
    textView.click()
    textView.typeKey("a", modifierFlags: .command)
    textView.typeText(value)
  }

  @MainActor
  private func transcriptInteractionElement(in app: XCUIApplication) -> XCUIElement {
    let transcriptTextView = app.textViews["subtitle-transcript-text-view"]
    if transcriptTextView.exists {
      return transcriptTextView
    }

    let demoSubtitleContainer = app.scrollViews["subtitle-edit-demo-subtitle-view"]
    if demoSubtitleContainer.exists {
      return demoSubtitleContainer
    }

    return app.scrollViews["subtitle-transcript-scroll-view"]
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
