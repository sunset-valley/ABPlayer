import XCTest

final class SubtitleSentenceNavigationUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testBracketShortcutsSeekBetweenSentences() {
    let app = launchApp()

    let seedSecondButton = app.buttons["subtitle-sentence-nav-seed-second"]
    XCTAssertTrue(seedSecondButton.waitForExistence(timeout: 4), "Seed button for second sentence not found")
    seedSecondButton.click()

    XCTAssertTrue(
      waitForCondition(timeout: 3) {
        self.metricInt(in: app, id: "subtitle-sentence-nav-active-cue") == 2
      },
      "Expected active cue to become 2 before local bracket test"
    )

    app.typeKey("[", modifierFlags: [])
    XCTAssertTrue(
      waitForCondition(timeout: 3) {
        self.metricInt(in: app, id: "subtitle-sentence-nav-active-cue") == 1
      },
      "Expected '[' to seek to previous sentence"
    )

    app.typeKey("]", modifierFlags: [])
    XCTAssertTrue(
      waitForCondition(timeout: 3) {
        self.metricInt(in: app, id: "subtitle-sentence-nav-active-cue") == 2
      },
      "Expected ']' to seek to next sentence"
    )
  }

  @MainActor
  func testOptionBracketShortcutsTriggerGlobalSentenceNavigation() {
    let app = launchApp()

    let seedSecondButton = app.buttons["subtitle-sentence-nav-seed-second"]
    XCTAssertTrue(seedSecondButton.waitForExistence(timeout: 4), "Seed button for second sentence not found")
    seedSecondButton.click()

    XCTAssertTrue(
      waitForCondition(timeout: 3) {
        self.metricInt(in: app, id: "subtitle-sentence-nav-active-cue") == 2
      },
      "Expected active cue to become 2 before option bracket test"
    )

    app.typeKey("[", modifierFlags: .option)
    XCTAssertTrue(
      waitForCondition(timeout: 3) {
        self.metricInt(in: app, id: "subtitle-sentence-nav-active-cue") == 1
      },
      "Expected option+[ to seek to previous sentence"
    )

    app.typeKey("]", modifierFlags: .option)
    XCTAssertTrue(
      waitForCondition(timeout: 3) {
        self.metricInt(in: app, id: "subtitle-sentence-nav-active-cue") == 2
      },
      "Expected option+] to seek to next sentence"
    )
  }

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += [
      "-ApplePersistenceIgnoreState", "YES",
      "--ui-testing", "--ui-testing-subtitle-sentence-navigation",
    ]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_SUBTITLE_SENTENCE_NAVIGATION"] = "1"

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)

    let loaded = app.staticTexts["subtitle-sentence-nav-demo-title"].waitForExistence(timeout: 20)
    XCTAssertTrue(loaded, "Subtitle sentence navigation demo did not load. UI tree:\n\(app.debugDescription)")
    return app
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
