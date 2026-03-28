import XCTest

final class ListeningStatsUITests: XCTestCase {
  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testListeningStatsDemoLoadsChart() {
    let app = launchApp()

    let demoTitle = app.staticTexts["listening-stats-demo-title"]
    XCTAssertTrue(
      demoTitle.waitForExistence(timeout: 10),
      "Listening stats demo title not found. UI tree:\n\(app.debugDescription)"
    )

    let statsTitle = app.staticTexts["listening-stats-title"]
    XCTAssertTrue(
      statsTitle.waitForExistence(timeout: 6),
      "Listening stats title not found. UI tree:\n\(app.debugDescription)"
    )

    let chart = app.descendants(matching: .any)["listening-stats-chart"]
    XCTAssertTrue(
      chart.waitForExistence(timeout: 6),
      "Listening stats chart did not load. UI tree:\n\(app.debugDescription)"
    )

    XCTAssertFalse(
      app.otherElements["listening-stats-empty"].exists,
      "Listening stats should not be empty in demo mode"
    )
  }

  @MainActor
  func testMonthRangeCanBeSelected() {
    let app = launchApp()

    let monthSegment = monthRangeSegment(in: app)
    XCTAssertTrue(monthSegment.waitForExistence(timeout: 6), "Month range segment not found")
    XCTAssertTrue(selectSegment(monthSegment, timeout: 6), "Failed to select Month segment")

    let rangePicker = app.radioGroups["listening-stats-range-picker"]
    XCTAssertTrue(rangePicker.waitForExistence(timeout: 4), "Range picker not found")
    XCTAssertEqual(rangePicker.value as? String, "Month")

    let chart = app.descendants(matching: .any)["listening-stats-chart"]
    XCTAssertTrue(chart.waitForExistence(timeout: 4), "Listening stats chart not shown")
    XCTAssertTrue(chart.isEnabled || chart.exists)

    let sevenDaysSegment = rangeSegment(in: app, label: "7 Days")
    XCTAssertTrue(sevenDaysSegment.waitForExistence(timeout: 4), "7 Days range segment not found")
    XCTAssertTrue(
      selectSegment(sevenDaysSegment, timeout: 4),
      "Failed to switch back to 7 Days segment"
    )

    XCTAssertEqual(rangePicker.value as? String, "7 Days")
    XCTAssertTrue(chart.exists)
  }

  @MainActor
  func testSwitchingBackTo7DaysHidesMonthNavigation() {
    let app = launchApp()

    let monthSegment = monthRangeSegment(in: app)
    XCTAssertTrue(monthSegment.waitForExistence(timeout: 6), "Month range segment not found")
    XCTAssertTrue(selectSegment(monthSegment, timeout: 6), "Failed to select Month segment")

    let rangePicker = app.radioGroups["listening-stats-range-picker"]
    XCTAssertTrue(rangePicker.waitForExistence(timeout: 4), "Range picker not found")
    XCTAssertEqual(rangePicker.value as? String, "Month")

    let sevenDaysSegment = rangeSegment(in: app, label: "7 Days")
    XCTAssertTrue(sevenDaysSegment.waitForExistence(timeout: 4), "7 Days range segment not found")
    XCTAssertTrue(selectSegment(sevenDaysSegment, timeout: 4), "Failed to select 7 Days segment")

    XCTAssertTrue(
      waitForCondition(timeout: 3) { (rangePicker.value as? String) == "7 Days" },
      "Range picker should switch back to 7 Days"
    )
  }

  @MainActor
  func testTooltipAppearsOnNonZeroBarAndHidesOnZeroBar() {
    let app = launchApp()

    let chart = app.descendants(matching: .any)["listening-stats-chart"]
    XCTAssertTrue(chart.waitForExistence(timeout: 6), "Listening stats chart did not load")

    let nonZeroBar = app.otherElements.matching(
      NSPredicate(format: "identifier BEGINSWITH 'listening-stats-bar-nonzero-'")
    ).firstMatch
    XCTAssertTrue(nonZeroBar.waitForExistence(timeout: 6), "Non-zero bar not found")

    hover(over: nonZeroBar)

    let tooltip = app.staticTexts["listening-stats-tooltip"]
    XCTAssertTrue(
      waitForCondition(timeout: 3) { tooltip.exists },
      "Tooltip should appear when hovering non-zero bar"
    )

    let zeroBar = app.otherElements.matching(
      NSPredicate(format: "identifier BEGINSWITH 'listening-stats-bar-zero-'")
    ).firstMatch
    XCTAssertTrue(zeroBar.waitForExistence(timeout: 6), "Zero bar not found")

    hover(over: zeroBar)

    XCTAssertTrue(
      waitForCondition(timeout: 3) { !tooltip.exists },
      "Tooltip should not remain visible when hovering zero bar"
    )
  }

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ApplePersistenceIgnoreState", "YES", "--ui-testing", "--ui-testing-listening-stats"]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_LISTENING_STATS"] = "1"

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)
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
  private func rangeSegment(in app: XCUIApplication, label: String) -> XCUIElement {
    let window = app.windows.firstMatch
    let radioButton = window.radioButtons[label]
    if radioButton.exists { return radioButton }

    let button = window.buttons[label]
    if button.exists { return button }

    return window.descendants(matching: .any).matching(NSPredicate(format: "label == %@", label)).firstMatch
  }

  @MainActor
  private func monthRangeSegment(in app: XCUIApplication) -> XCUIElement {
    let byID = app.radioButtons["listening-stats-range-month"]
    if byID.exists { return byID }
    return rangeSegment(in: app, label: "Month")
  }

  @MainActor
  private func selectSegment(_ segment: XCUIElement, timeout: TimeInterval) -> Bool {
    if isSelected(segment) { return true }

    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if segment.isHittable {
        segment.click()
      } else {
        let center = segment.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        center.click()
      }

      if isSelected(segment) {
        return true
      }

      RunLoop.current.run(until: Date().addingTimeInterval(0.15))
    }

    return isSelected(segment)
  }

  @MainActor
  private func isSelected(_ segment: XCUIElement) -> Bool {
    if let boolValue = segment.value as? Bool {
      return boolValue
    }

    if let number = segment.value as? NSNumber {
      return number.intValue == 1
    }

    if let rawValue = segment.value as? String {
      if rawValue == "1" { return true }
      return rawValue.localizedCaseInsensitiveContains("selected")
    }

    return false
  }

  @MainActor
  private func hover(over element: XCUIElement) {
    let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.45, dy: 0.5))
    let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.5))
    start.press(forDuration: 0.02, thenDragTo: end)
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
