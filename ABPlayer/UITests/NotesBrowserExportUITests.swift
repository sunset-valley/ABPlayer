import Foundation
import XCTest

final class NotesBrowserExportUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testExportCSVForSelectedAudioWritesExpectedContent() throws {
    let exportURL = temporaryExportURL()
    defer {
      try? FileManager.default.removeItem(at: exportURL)
    }

    let app = launchApp(exportPath: exportURL.path)

    let demoWindow = app.windows.containing(
      .staticText,
      identifier: "notes-browser-export-demo-title"
    ).firstMatch
    XCTAssertTrue(demoWindow.waitForExistence(timeout: 6), "Demo window not found. UI tree:\n\(app.debugDescription)")

    let exportButton = demoWindow.descendants(matching: .button)
      .matching(identifier: "notes-browser-export-csv-button")
      .firstMatch
    XCTAssertTrue(exportButton.waitForExistence(timeout: 6), "Export button not found. UI tree:\n\(app.debugDescription)")
    XCTAssertFalse(exportButton.isEnabled, "Export should be disabled before selecting exportable item")

    let allAudiosLabel = demoWindow.staticTexts["All Audios"]
    XCTAssertTrue(allAudiosLabel.waitForExistence(timeout: 6), "All Audios source not found. UI tree:\n\(app.debugDescription)")
    allAudiosLabel.click()

    let middleList = demoWindow.outlines["notes-browser-middle-list"]
    let mediaLabel = middleList.staticTexts["UI Export Media"]
    XCTAssertTrue(mediaLabel.waitForExistence(timeout: 6), "Audio item not found. UI tree:\n\(app.debugDescription)")
    mediaLabel.click()

    XCTAssertTrue(
      waitForCondition(timeout: 4) { exportButton.isEnabled },
      "Export button did not become enabled after selecting audio item"
    )

    clickButtonWhenReady(exportButton, in: app, timeout: 4)

    XCTAssertTrue(
      waitForCondition(timeout: 4) { FileManager.default.fileExists(atPath: exportURL.path) },
      "CSV file was not written to expected output path"
    )

    let content = try String(contentsOf: exportURL, encoding: .utf8)
    let expected = "title,note\nSnapshot title,Annotation note"
    XCTAssertEqual(content, expected)
  }

  @MainActor
  func testExportCSVRespectsStylePresetFilter() throws {
    let exportURL = temporaryExportURL()
    defer {
      try? FileManager.default.removeItem(at: exportURL)
    }

    let app = launchApp(exportPath: exportURL.path)

    let demoWindow = app.windows.containing(
      .staticText,
      identifier: "notes-browser-export-demo-title"
    ).firstMatch
    XCTAssertTrue(demoWindow.waitForExistence(timeout: 6), "Demo window not found. UI tree:\n\(app.debugDescription)")

    let allAudiosLabel = demoWindow.staticTexts["All Audios"]
    XCTAssertTrue(allAudiosLabel.waitForExistence(timeout: 6), "All Audios source not found. UI tree:\n\(app.debugDescription)")
    allAudiosLabel.click()

    let middleList = demoWindow.outlines["notes-browser-middle-list"]
    let mediaLabel = middleList.staticTexts["UI Export Media"]
    XCTAssertTrue(mediaLabel.waitForExistence(timeout: 6), "Audio item not found. UI tree:\n\(app.debugDescription)")
    mediaLabel.click()

    let styleSegment = demoWindow.radioButtons["Underline"]
    XCTAssertTrue(styleSegment.waitForExistence(timeout: 6), "Underline filter segment not found. UI tree:\n\(app.debugDescription)")
    styleSegment.click()

    let exportButton = demoWindow.descendants(matching: .button)
      .matching(identifier: "notes-browser-export-csv-button")
      .firstMatch
    XCTAssertTrue(exportButton.waitForExistence(timeout: 6), "Export button not found. UI tree:\n\(app.debugDescription)")
    XCTAssertTrue(
      waitForCondition(timeout: 4) { exportButton.isEnabled },
      "Export button did not become enabled after selecting style filter"
    )

    clickButtonWhenReady(exportButton, in: app, timeout: 4)

    XCTAssertTrue(
      waitForCondition(timeout: 4) { FileManager.default.fileExists(atPath: exportURL.path) },
      "CSV file was not written to expected output path"
    )

    let content = try String(contentsOf: exportURL, encoding: .utf8)
    let expected = "title,note\nSnapshot title,Annotation note"
    XCTAssertEqual(content, expected)
  }

  @MainActor
  private func launchApp(exportPath: String) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "--ui-testing", "--ui-testing-notes-export"]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_NOTES_EXPORT"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_NOTES_EXPORT_OUTPUT_PATH"] = exportPath

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)
    app.activate()

    let loaded = app.staticTexts["notes-browser-export-demo-title"].waitForExistence(timeout: 20)
    XCTAssertTrue(loaded, "Notes export demo did not load. UI tree:\n\(app.debugDescription)")
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
  private func clickButtonWhenReady(_ button: XCUIElement, in app: XCUIApplication, timeout: TimeInterval) {
    XCTAssertTrue(
      waitForCondition(timeout: timeout) { button.exists && button.isEnabled },
      "Button did not become enabled in time. UI tree:\n\(app.debugDescription)"
    )

    app.activate()

    if button.isHittable {
      button.click()
      return
    }

    let center = button.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
    center.click()
  }

  @MainActor
  private func temporaryExportURL() -> URL {
    let temporaryDirectory = FileManager.default.temporaryDirectory
    let fileName = "notes-export-ui-test-\(UUID().uuidString).csv"
    return temporaryDirectory.appendingPathComponent(fileName)
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
