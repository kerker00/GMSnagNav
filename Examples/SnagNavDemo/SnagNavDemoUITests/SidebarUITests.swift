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

  // MARK: Search

  private func search(_ text: String) {
    let field = app.searchFields.firstMatch
    XCTAssertTrue(field.waitForExistence(timeout: 5), "No search field")
    // Right after launch, the first keystrokes can get lost; type until the field has the text.
    for _ in 0..<3 where (field.value as? String) != text {
      #if os(macOS)
        field.click()
      #else
        field.tap()
      #endif
      field.typeText(text)
    }
    XCTAssertEqual(field.value as? String, text)
  }

  func testSearchingShowsOnlyMatchesAndTheFoldersLeadingToThem() {
    search("Contract")
    // Contract lives in Work › Clients › Globex, which the search opens.
    XCTAssertTrue(row("Contract").waitForExistence(timeout: 5))
    XCTAssertTrue(row("Globex").exists)
    XCTAssertFalse(row("Inbox").exists)
    XCTAssertFalse(row("Acme").exists)
  }

  #if os(macOS)
    func testDraggingIsOffWhileSearching() {
      search("Contract")
      XCTAssertTrue(row("Contract").waitForExistence(timeout: 5))
      drag("Contract", onto: "Work")
      select("Contract")
      assertDetailLocation("Work › Clients › Globex › Contract")
    }
  #endif

  // MARK: Context menus

  #if os(macOS)
    func testRightClickingARowShowsItsContextMenu() {
      let window = app.windows.firstMatch
      let report = row("Weekly Report")
      XCTAssertTrue(report.waitForExistence(timeout: 5))
      report.rightClick()
      // The row's own menu, not the one for empty space, which only offers adding.
      XCTAssertTrue(window.menuItems["Move to"].waitForExistence(timeout: 3))
      XCTAssertTrue(window.menuItems["Delete"].exists)
      app.typeKey(.escape, modifierFlags: [])
    }
  #endif

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
    /// Long-presses a row and drags it to a point within another row: `0.5` is the middle, which
    /// drops onto the row; `0.05` its top edge, which inserts before it.
    private func drag(_ source: String, to target: String, at verticalOffset: CGFloat = 0.5) {
      // The context menu shares the long press with dragging; whether a synthesized press opens
      // the menu or lifts the row depends on timing. Drag tests therefore run without the menu,
      // which `testLongPressShowsTheContextMenu` covers on its own.
      if !app.launchArguments.contains("-disable-context-menus") {
        app.terminate()
        app.launchArguments.append("-disable-context-menus")
        app.launch()
      }
      let source = row(source)
      // Offsets refer to the whole list cell; the row's label is shorter than its cell.
      let target = cell(containing: target)
      XCTAssertTrue(source.waitForExistence(timeout: 5))
      XCTAssertTrue(target.waitForExistence(timeout: 5))
      source.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        .press(
          forDuration: 1.0,
          thenDragTo: target.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: verticalOffset)),
          withVelocity: .slow, thenHoldForDuration: 0.5)
    }

    private func cell(containing name: String) -> XCUIElement {
      app.cells.containing(.any, identifier: "sidebar-row-\(name)").firstMatch
    }

    func testSelectingOpensTheDetailAndNavigatingBackAllowsReopening() throws {
      select("Inbox")
      assertDetailLocation("Inbox")
      let back = app.navigationBars.buttons["Library"]
      guard back.waitForExistence(timeout: 2) else {
        throw XCTSkip("The split view is not collapsed on this device.")
      }
      back.tap()
      XCTAssertTrue(row("Inbox").waitForExistence(timeout: 5))
      // The selection was cleared on the way back, so the same row opens again.
      select("Inbox")
      assertDetailLocation("Inbox")
    }

    func testLongPressShowsTheContextMenu() {
      // Without animations, the app becomes idle while the menu is open.
      app.terminate()
      app.launchArguments.append("-disable-animations")
      app.launch()
      let inbox = row("Inbox")
      XCTAssertTrue(inbox.waitForExistence(timeout: 5))
      inbox.press(forDuration: 1.2)
      XCTAssertTrue(app.buttons["Delete"].waitForExistence(timeout: 5), "No context menu appeared")
      XCTAssertTrue(app.buttons["Move to"].exists)
    }

    func testSwipingARowLeftDeletesIt() {
      let ideas = cell(containing: "Ideas")
      XCTAssertTrue(ideas.waitForExistence(timeout: 5))
      ideas.swipeLeft()
      let delete = app.buttons["Delete"].firstMatch
      XCTAssertTrue(delete.waitForExistence(timeout: 5), "No swipe action appeared")
      delete.tap()
      XCTAssertTrue(row("Ideas").waitForNonExistence(timeout: 5))
    }

    func testDroppingARowOntoAFolderMovesItInside() {
      // Archive is an empty folder, so only a drop onto it can place Inbox inside.
      drag("Inbox", to: "Archive")
      XCTAssertTrue(row("Inbox").waitForExistence(timeout: 5))
      select("Inbox")
      assertDetailLocation("Archive › Inbox")
    }

    func testDroppingAtTheTopEdgeOfARowInsertsBeforeIt() {
      drag("Ideas", to: "Work", at: 0.05)
      XCTAssertLessThan(row("Ideas").frame.minY, row("Work").frame.minY)
      select("Ideas")
      assertDetailLocation("Ideas")
    }

    func testDroppingOntoADocumentInsertsNextToIt() {
      // Recipes is a document inside Personal, so the demo redirects the drop next to it.
      drag("Inbox", to: "Recipes")
      select("Inbox")
      assertDetailLocation("Personal › Inbox")
    }
  #endif
}
