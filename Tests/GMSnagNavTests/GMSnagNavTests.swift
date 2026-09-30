import Testing

@testable import GMSnagNav

@Test func packageExposesVersion() {
    #expect(!GMSnagNav.version.isEmpty)
}
