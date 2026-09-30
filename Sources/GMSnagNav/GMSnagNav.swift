/// GMSnagNav provides a nested, drag-and-drop capable outline for SwiftUI.
///
/// On macOS the outline is backed by a native `NSOutlineView`; on iOS and iPadOS it is rendered
/// with SwiftUI. The host app owns its tree and decides what every drop means — the package only
/// supplies the interaction mechanics.
public enum GMSnagNav {
    /// The version of the package, following Semantic Versioning.
    public static let version = "0.0.0"
}
