import XCTest

/// Takes the screenshots shown in the README, in light and dark appearance.
///
/// Skipped unless the environment variable `README_SCREENSHOTS` is set; run
/// `Scripts/readme-screenshots.sh`, which sets it and copies the images to `docs/images`.
@MainActor
final class ReadmeScreenshots: XCTestCase {
  override func setUp() async throws {
    try XCTSkipUnless(
      ProcessInfo.processInfo.environment["README_SCREENSHOTS"] != nil,
      "Set README_SCREENSHOTS to take the README screenshots.")
    continueAfterFailure = false
  }

  func testLightAppearance() {
    takeScreenshot(appearance: "light")
  }

  func testDarkAppearance() {
    takeScreenshot(appearance: "dark")
  }

  /// Shows the whole sample library with a nested document selected, and attaches a screenshot
  /// named after the platform and appearance, such as `macos-light`.
  private func takeScreenshot(appearance: String) {
    let app = XCUIApplication()
    app.launchArguments = ["-ui-testing", "-DemoColorScheme", appearance]
    app.launch()
    #if os(macOS)
      if !app.windows.firstMatch.waitForExistence(timeout: 3) {
        app.typeKey("n", modifierFlags: .command)
        XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 5), "No window opened")
      }
    #endif

    #if os(macOS)
      let outlineMenu = app.menuButtons["Outline"].firstMatch
    #else
      let outlineMenu = app.buttons["Outline"].firstMatch
    #endif
    XCTAssertTrue(outlineMenu.waitForExistence(timeout: 5), "No outline menu")
    #if os(macOS)
      outlineMenu.click()
      app.menuItems["Expand All"].firstMatch.click()
    #else
      outlineMenu.tap()
      app.buttons["Expand All"].firstMatch.tap()
    #endif

    let proposal = app.descendants(matching: .any)
      .matching(identifier: "sidebar-row-Proposal").firstMatch
    XCTAssertTrue(proposal.waitForExistence(timeout: 5), "The folders did not expand")
    #if os(macOS)
      proposal.click()
    #else
      proposal.tap()
    #endif
    #if os(macOS)
      // The source list shows its selection in the accent color only in the active window.
      app.activate()
    #endif
    // Let the selection and the detail view settle.
    RunLoop.current.run(until: Date().addingTimeInterval(1.5))

    #if os(macOS)
      let screenshot = app.windows.firstMatch.screenshot()
      let platform = "macos"
    #else
      let screenshot = XCUIScreen.main.screenshot()
      let platform = UIDevice.current.userInterfaceIdiom == .pad ? "ipad" : "iphone"
    #endif
    let attachment = XCTAttachment(screenshot: screenshot)
    attachment.name = "\(platform)-\(appearance)"
    attachment.lifetime = .keepAlways
    add(attachment)
  }
}
