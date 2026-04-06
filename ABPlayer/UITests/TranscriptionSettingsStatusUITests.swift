import XCTest

final class TranscriptionSettingsStatusUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testModelReadyScenarioShowsDownloadedStatusInsteadOfDownloadButton() {
    let app = launchApp(scenario: "model-ready")

    let transcriptionTab = app.windows.firstMatch.buttons["Transcription"]
    XCTAssertTrue(transcriptionTab.waitForExistence(timeout: 6), "Transcription tab missing. UI tree:\n\(app.debugDescription)")
    transcriptionTab.click()

    let downloadedStatus = app.descendants(matching: .any)
      .matching(identifier: "transcription-model-status-downloaded")
      .firstMatch
    XCTAssertTrue(
      waitForCondition(timeout: 8) {
        downloadedStatus.exists
      },
      "Downloaded status did not appear. UI tree:\n\(app.debugDescription)"
    )

    let downloadButton = app.descendants(matching: .any)
      .matching(identifier: "transcription-model-status-download-button")
      .firstMatch
    XCTAssertFalse(
      downloadButton.exists,
      "Download button should not be shown when model is detected in selected directory"
    )
  }

  @MainActor
  private func launchApp(scenario: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ApplePersistenceIgnoreState", "YES",
      "--ui-testing", "--ui-testing-transcription-settings-status",
      "--ui-testing-transcription-settings-status-scenario", scenario,
    ]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_TRANSCRIPTION_SETTINGS_STATUS"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_TRANSCRIPTION_SETTINGS_STATUS_SCENARIO"] = scenario

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    _ = app.windows.firstMatch.waitForExistence(timeout: 8)

    let loaded = app.staticTexts["transcription-settings-demo-title"].waitForExistence(timeout: 20)
    XCTAssertTrue(loaded, "Transcription settings demo did not load. UI tree:\n\(app.debugDescription)")
    return app
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
