import SwiftUI
import Testing

@testable import GMSnagNav

@MainActor
@Suite struct SelectionRevealDriverTests {
  private let tree = OutlineTree(sampleRoots, children: \.children)
  private let driver = OutlineSelectionReveal<String>()
  private var host = Host()

  private final class Host {
    var expanded: Set<String> = []
    var binding: Binding<Set<String>> {
      Binding(get: { self.expanded }, set: { self.expanded = $0 })
    }
  }

  private func select(_ ids: Set<String>, reveals: Bool = true) {
    driver.hostSelected(ids, in: tree, expansion: host.binding, reveals: reveals)
  }

  @Test func aNewHostSelectionSupersedesQueuedExpansion() async {
    select(["a2x"])
    select(["c"])
    await driver.settled()
    #expect(host.expanded.isEmpty)
    #expect(driver.pending == "c")
  }

  @Test func userSelectionCancelsQueuedExpansionAndScroll() async {
    select(["a2x"])
    driver.userSelected(["c"])
    await driver.settled()
    #expect(host.expanded.isEmpty)
    #expect(driver.pending == nil)
  }

  @Test func clearingTheHostSelectionCancelsQueuedExpansion() async {
    select(["a2x"])
    select([])
    await driver.settled()
    #expect(host.expanded.isEmpty)
    #expect(driver.pending == nil)
  }

  @Test func disablingRevealCancelsQueuedExpansion() async {
    select(["a2x"])
    select(["a2x"], reveals: false)
    await driver.settled()
    #expect(host.expanded.isEmpty)
    #expect(driver.pending == nil)
  }

  @Test func removingTheSelectedTargetCancelsQueuedExpansion() async {
    select(["a2x"])
    driver.hostSelected(
      ["a2x"], in: OutlineTree<TestItem>([], children: \.children),
      expansion: host.binding, reveals: true)
    await driver.settled()
    #expect(host.expanded.isEmpty)
    #expect(driver.pending == nil)
  }

  @Test func detachmentCancelsQueuedBindingWrites() async {
    select(["a2x"])
    driver.cancel()
    // Give cancelled tasks a chance to run as well as waiting for current work.
    await Task { @MainActor in }.value
    #expect(host.expanded.isEmpty)
    #expect(driver.pending == nil)
  }

  @Test func anUnchangedUpdateKeepsTheCurrentReveal() async {
    select(["a2x"])
    select(["a2x"])
    host.expanded.insert("b")
    await driver.settled()
    #expect(host.expanded == ["a", "a2", "b"])
    #expect(driver.pending == "a2x")
    driver.didReveal()
    select(["a2x"])
    #expect(driver.pending == nil)
  }

  @Test func aStructureChangeRecomputesQueuedAncestors() async {
    select(["a2x"])
    let moved = OutlineTree([TestItem.group("b", [.leaf("a2x")])], children: \.children)
    driver.hostSelected(["a2x"], in: moved, expansion: host.binding, reveals: true)
    await driver.settled()
    #expect(host.expanded == ["b"])
    #expect(driver.pending == "a2x")
  }
}
