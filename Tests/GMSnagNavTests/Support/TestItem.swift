/// A minimal tree element for tests.
struct TestItem: Identifiable, Equatable {
  let id: String
  var children: [TestItem]?

  /// A leaf that can never have children.
  static func leaf(_ id: String) -> TestItem {
    TestItem(id: id, children: nil)
  }

  /// A container; an empty `children` list describes an expandable container without children.
  static func group(_ id: String, _ children: [TestItem] = []) -> TestItem {
    TestItem(id: id, children: children)
  }
}

/// A sample tree used across tests:
///
/// ```text
/// - a
///   - a1
///   - a2
///     - a2x
/// - b (empty group)
/// - c
/// ```
let sampleRoots: [TestItem] = [
  .group("a", [.leaf("a1"), .group("a2", [.leaf("a2x")])]),
  .group("b"),
  .leaf("c"),
]
