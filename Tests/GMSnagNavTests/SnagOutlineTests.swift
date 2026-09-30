import SwiftUI
import Testing

@testable import GMSnagNav

/// Checks that the public initializers accept the call shapes promised in the documentation.
@MainActor
@Suite struct SnagOutlineTests {
  @Test func acceptsKeyPathsAndClosuresForChildren() {
    var single: String?
    var multiple: Set<String> = []
    var expansion: Set<String> = []
    let singleBinding = Binding(get: { single }, set: { single = $0 })
    let multipleBinding = Binding(get: { multiple }, set: { multiple = $0 })
    let expansionBinding = Binding(get: { expansion }, set: { expansion = $0 })

    _ = SnagOutline(sampleRoots, children: \.children, selection: singleBinding) { Text($0.id) }
    _ = SnagOutline(
      sampleRoots, children: \.children, selection: multipleBinding, expansion: expansionBinding
    ) { Text($0.id) }
    _ = SnagOutline(sampleRoots, children: { $0.children }, rowContent: { Text($0.id) })
  }

  @Test func bindsSelectionModes() {
    var single: String? = "a"
    let outline = SnagOutline(
      sampleRoots, children: \.children, selection: Binding(get: { single }, set: { single = $0 })
    ) { Text($0.id) }

    guard case .single(let binding) = outline.selection else {
      Issue.record("Expected single selection")
      return
    }
    binding.wrappedValue = "c"
    #expect(single == "c")

    let unselectable = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
    guard case .none = unselectable.selection else {
      Issue.record("Expected no selection")
      return
    }
  }
}
