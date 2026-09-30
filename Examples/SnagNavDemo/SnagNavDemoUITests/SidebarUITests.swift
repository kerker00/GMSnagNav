import XCTest

/// Drives the real demo app: selection, and on macOS genuine mouse drags.
///
/// The app starts with `-ui-testing`, which resets its settings, so every test sees the sample
/// library with the top-level folders expanded.
@MainActor
final class SidebarUITests: XCTestCase {
  private var app: XCUIApplication!

  override func setUp() async throws {
    continueAfterFailure = false
    app = XCUIApplication()
    app.launchArguments = ["-ui-testing"]
    app.launch()
    #if os(macOS)
      // SwiftUI may relaunch without a window when the previous run closed it; open a new one.
      if !app.windows.firstMatch.waitForExistence(timeout: 3) {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), "No window opened")
      }
    #endif
  }

  // MARK: Helpers

  private func row(_ name: String) -> XCUIElement {
    app.descendants(matching: .any).matching(identifier: "sidebar-row-\(name)").firstMatch
  }

  /// The location shown in the detail view, such as "Archive › Inbox".
  private var detailLocation: String {
    let element = app.descendants(matching: .any).matching(identifier: "detail-location").firstMatch
    XCTAssertTrue(element.waitForExistence(timeout: 5), "The detail view shows no location")
    let text = (element.value as? String).flatMap { $0.isEmpty ? nil : $0 } ?? element.label
    // On iOS, the form row combines its label and value into one element: "Location, Inbox".
    let prefix = "Location, "
    return text.hasPrefix(prefix) ? String(text.dropFirst(prefix.count)) : text
  }

  /// Waits until the detail view shows `expected`; the view may still show the previous
  /// selection right after a click.
  private func assertDetailLocation(
    _ expected: String, file: StaticString = #filePath, line: UInt = #line
  ) {
    let deadline = Date().addingTimeInterval(5)
    var location = detailLocation
    while location != expected, Date() < deadline {
      RunLoop.current.run(until: Date().addingTimeInterval(0.2))
      location = detailLocation
    }
    XCTAssertEqual(location, expected, file: file, line: line)
  }

  private func select(_ name: String) {
    let row = row(name)
    XCTAssertTrue(row.waitForExistence(timeout: 5), "No row named \(name)")
    #if os(macOS)
      row.click()
    #else
      row.tap()
    #endif
  }

  // MARK: Selection

  func testSelectingADocumentShowsItsDetails() {
    select("Inbox")
    assertDetailLocation("Inbox")
  }

  func testSelectingANestedDocumentShowsItsPath() {
    select("Weekly Report")
    assertDetailLocation("Work › Weekly Report")
  }

  // MARK: Drag and drop

  #if os(macOS)
    private func drag(_ source: String, onto target: String) {
      let source = row(source)
      let target = row(target)
      XCTAssertTrue(source.waitForExistence(timeout: 5))
      XCTAssertTrue(target.waitForExistence(timeout: 5))
      // The mouse-based variant: `press(forDuration:thenDragTo:)` synthesizes touches, which
      // start no AppKit drag session.
      source.click(forDuration: 0.6, thenDragTo: target)
    }

    func testDraggingADocumentOntoAFolderMovesItInside() {
      drag("Inbox", onto: "Archive")
      // The demo opens the folder that received the drop.
      XCTAssertTrue(row("Inbox").waitForExistence(timeout: 5))
      select("Inbox")
      assertDetailLocation("Archive › Inbox")
    }

    func testDraggingAFolderIntoItsOwnSubfolderIsRejected() {
      drag("Work", onto: "Clients")
      select("Work")
      assertDetailLocation("Work")
      select("Clients")
      assertDetailLocation("Work › Clients")
    }

    func testDroppingOntoADocumentInsertsNextToIt() {
      drag("Inbox", onto: "Recipes")
      select("Inbox")
      // Recipes is a document inside Personal, so Inbox lands next to it, not inside it.
      assertDetailLocation("Personal › Inbox")
      XCTAssertGreaterThan(row("Inbox").frame.minY, row("Recipes").frame.minY)
    }

    func testMovedFolderKeepsItsExpansion() {
      // Personal is expanded, so its children are visible; after the move they still are.
      drag("Personal", onto: "Archive")
      XCTAssertTrue(row("Recipes").waitForExistence(timeout: 5))
      select("Recipes")
      assertDetailLocation("Archive › Personal › Recipes")
    }
  #endif

  #if os(iOS)
    /// Long-presses a row and moves it onto another row's place, like reordering in a list.
    private func move(_ source: String, to target: String) {
      let source = row(source)
      let target = row(target)
      XCTAssertTrue(source.waitForExistence(timeout: 5))
      XCTAssertTrue(target.waitForExistence(timeout: 5))
      source.press(
        forDuration: 1.0, thenDragTo: target, withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    func testMovingARowUpReordersTheRootLevel() {
      move("Ideas", to: "Work")
      XCTAssertLessThan(row("Ideas").frame.minY, row("Work").frame.minY)
      select("Ideas")
      assertDetailLocation("Ideas")
    }

    func testMovingARowIntoAnExpandedFolderReparentsIt() {
      // Rows: … Personal, Travel, Recipes, Archive, Inbox. Moving Inbox up onto Recipes places it
      // before Recipes, inside Personal.
      move("Inbox", to: "Recipes")
      select("Inbox")
      assertDetailLocation("Personal › Inbox")
    }
  #endif
}
