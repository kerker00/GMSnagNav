import Foundation
import Testing

@testable import GMSnagNav

/// The package's own texts, which VoiceOver reads for the rows' disclosure indicators on iOS.
@Suite struct LocalizationTests {
  @Test(arguments: [
    ("en", "Expanded", "Expanded"), ("en", "Collapse", "Collapse"),
    ("de", "Expanded", "Erweitert"), ("de", "Collapsed", "Reduziert"),
    ("de", "Expand", "Erweitern"), ("de", "Collapse", "Reduzieren"),
  ])
  func translatesDisclosureTexts(language: String, key: String, expected: String) throws {
    let path = try #require(Bundle.module.path(forResource: language, ofType: "lproj"))
    let bundle = try #require(Bundle(path: path))
    #expect(bundle.localizedString(forKey: key, value: nil, table: nil) == expected)
  }
}
