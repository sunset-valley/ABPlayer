import AppKit
import XCTest

final class AnnotationMenuUITests: XCTestCase {
  private let styleDeletePredicate = NSPredicate(format: "identifier BEGINSWITH 'style-delete-'")
  private let styleNamePredicate = NSPredicate(format: "identifier BEGINSWITH 'style-name-'")

  override func setUpWithError() throws {
    continueAfterFailure = false
  }

  @MainActor
  func testAddStyle() {
    let app = launchApp()
    openStyleManagementIfNeeded(in: app)
    let before = styleCount(in: app)
    let addButton = styleAddButton(in: app)
    XCTAssertTrue(addButton.waitForExistence(timeout: 4), "Add style button not found")
    addButton.click()

    XCTAssertTrue(
      waitForCondition(timeout: 3) { self.styleCount(in: app) == before + 1 },
      "Style count did not increase from \(before). UI tree:\n\(app.debugDescription)"
    )
  }

  @MainActor
  func testRenameStyle() {
    let app = launchApp()
    openStyleManagementIfNeeded(in: app)
    let textField = firstStyleNameField(in: app)
    XCTAssertTrue(textField.waitForExistence(timeout: 4), "Style name field not found")

    replaceText(in: textField, with: "Renamed Style")

    XCTAssertTrue(
      waitForCondition(timeout: 2) { (textField.value as? String) == "Renamed Style" },
      "Style name was not updated. Actual value: \(String(describing: textField.value))"
    )
  }

  @MainActor
  private func replaceText(in textField: XCUIElement, with value: String) {
    textField.click()
    textField.typeKey("a", modifierFlags: .command)
    NSPasteboard.general.clearContents()
    NSPasteboard.general.setString(value, forType: .string)
    textField.typeKey("v", modifierFlags: .command)
    textField.typeKey(XCUIKeyboardKey.return, modifierFlags: [])
  }

  @MainActor
  func testChangeKind() {
    let app = launchApp()
    openStyleManagementIfNeeded(in: app)
    let kindPicker = firstKindPicker(in: app)
    XCTAssertTrue(kindPicker.waitForExistence(timeout: 4), "Style kind picker not found")

    kindPicker.click()
    app.menuItems["Background"].click()

    let value = kindPicker.value as? String
    let title = kindPicker.title
    XCTAssertTrue((value?.contains("Background") ?? false) || title.contains("Background"))
  }

  @MainActor
  func testCannotDeleteUsedStyle() {
    let app = launchApp()
    openStyleManagementIfNeeded(in: app)
    let deleteButton = firstDeleteButton(in: app)
    XCTAssertTrue(
      deleteButton.waitForExistence(timeout: 4),
      "Style delete button not found. UI tree:\n\(app.debugDescription)"
    )

    deleteButton.click()

    XCTAssertTrue(
      cannotDeleteStyleAlertExists(in: app, timeout: 2),
      "Cannot Delete Style alert did not appear. UI tree:\n\(app.debugDescription)"
    )
  }

  @MainActor
  func testExistingAnnotationStyleSelectionState() {
    let app = launchApp()
    let firstStyle = app.buttons["style-row-action-0"]
    let secondStyle = app.buttons["style-row-action-1"]

    XCTAssertTrue(firstStyle.waitForExistence(timeout: 4), "First style card not found")
    XCTAssertTrue(secondStyle.waitForExistence(timeout: 4), "Second style card not found")

    XCTAssertEqual(styleSelectionValue(for: firstStyle), "selected")
    XCTAssertEqual(styleSelectionValue(for: secondStyle), "unselected")

    secondStyle.click()

    XCTAssertTrue(
      waitForCondition(timeout: 2) {
        self.styleSelectionValue(for: firstStyle) == "unselected"
          && self.styleSelectionValue(for: secondStyle) == "selected"
      },
      "Style selection state did not switch after tapping second style"
    )
  }

  @MainActor
  private func styleCount(in app: XCUIApplication) -> Int {
    let scope = styleManagementScope(in: app)
    return scope.textFields.matching(styleNamePredicate).count
  }

  @MainActor
  private func styleSelectionValue(for styleButton: XCUIElement) -> String? {
    styleButton.value as? String
  }

  @MainActor
  private func waitForDemoLoaded(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
    let title = app.staticTexts["annotation-menu-demo-title"]
    let count = app.staticTexts["style-count"]
    let value = app.staticTexts["style-count-value"]

    if title.waitForExistence(timeout: timeout) {
      return true
    }

    if count.waitForExistence(timeout: 1) {
      return true
    }

    return value.waitForExistence(timeout: 1)
  }

  @MainActor
  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["--ui-testing", "--ui-testing-annotation-demo"]
    app.launchEnvironment["ABP_UI_TESTING"] = "1"
    app.launchEnvironment["ABP_UI_TESTING_ANNOTATION_DEMO"] = "1"

    if app.state == .runningForeground || app.state == .runningBackground {
      app.terminate()
    }

    app.launch()
    ensureWindowIsOpen(in: app)

    let loaded = waitForDemoLoaded(in: app, timeout: 20)
    if !loaded {
      XCTFail("Demo view did not load. UI tree:\n\(app.debugDescription)")
    }

    XCTAssertTrue(
      waitForStyleControls(in: app, timeout: 6),
      "Style controls did not load. UI tree:\n\(app.debugDescription)"
    )

    return app
  }

  @MainActor
  private func styleAddButton(in app: XCUIApplication) -> XCUIElement {
    let scope = styleManagementScope(in: app)
    let byID = scope.buttons["style-add"]
    if byID.exists { return byID }
    return scope.buttons["Add Style"]
  }

  @MainActor
  private func openStyleManagementIfNeeded(in app: XCUIApplication) {
    let panel = styleManagementPanel(in: app)
    if panel.exists {
      return
    }

    let toggle = app.buttons["style-manage-toggle"]
    XCTAssertTrue(toggle.waitForExistence(timeout: 3), "Manage style toggle not found")
    toggle.click()
    XCTAssertTrue(
      panel.waitForExistence(timeout: 5),
      "Style management panel not shown after tapping manage"
    )
  }

  @MainActor
  private func firstStyleNameField(in app: XCUIApplication) -> XCUIElement {
    let scope = styleManagementScope(in: app)
    let byID = scope.textFields["style-name-0"]
    if byID.exists { return byID }
    return scope.textFields.firstMatch
  }

  @MainActor
  private func firstKindPicker(in app: XCUIApplication) -> XCUIElement {
    let scope = styleManagementScope(in: app)
    let byID = scope.popUpButtons["style-kind-0"]
    if byID.exists { return byID }
    return scope.popUpButtons.firstMatch
  }

  @MainActor
  private func firstDeleteButton(in app: XCUIApplication) -> XCUIElement {
    let scope = styleManagementScope(in: app)
    let byID = scope.buttons["style-delete-0"]
    if byID.exists { return byID }

    let byPrefix = scope.buttons.matching(styleDeletePredicate).firstMatch
    if byPrefix.exists { return byPrefix }

    let byLabel = scope.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'Delete style'"))
      .firstMatch
    if byLabel.exists { return byLabel }

    return scope.descendants(matching: .any).matching(styleDeletePredicate).firstMatch
  }

  @MainActor
  private func waitForStyleControls(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
    if app.buttons["style-manage-toggle"].waitForExistence(timeout: timeout) {
      return true
    }

    if styleAddButton(in: app).waitForExistence(timeout: timeout) {
      return true
    }

    let hasName = firstStyleNameField(in: app).waitForExistence(timeout: 1)
    let hasPicker = firstKindPicker(in: app).waitForExistence(timeout: 1)
    let hasDelete = firstDeleteButton(in: app).waitForExistence(timeout: 1)
    return hasName || hasPicker || hasDelete
  }

  @MainActor
  private func styleManagementScope(in app: XCUIApplication) -> XCUIElement {
    let panel = styleManagementPanel(in: app)
    return panel.exists ? panel : app
  }

  @MainActor
  private func styleManagementPanel(in app: XCUIApplication) -> XCUIElement {
    let scrollPanel = app.scrollViews["style-manage-panel"]
    if scrollPanel.exists { return scrollPanel }
    return app.descendants(matching: .any)["style-manage-panel"]
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
  private func cannotDeleteStyleAlertExists(in app: XCUIApplication, timeout: TimeInterval) -> Bool {
    if app.alerts["Cannot Delete Style"].waitForExistence(timeout: timeout) {
      return true
    }
    if app.sheets["Cannot Delete Style"].waitForExistence(timeout: timeout) {
      return true
    }
    if app.sheets.staticTexts["Cannot Delete Style"].waitForExistence(timeout: timeout) {
      return true
    }
    return app.staticTexts["Cannot Delete Style"].waitForExistence(timeout: timeout)
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
