import Testing

@testable import GMSnagNav

/// Applies outline changes the way `NSOutlineView` does, and fails on invalid indices.
private struct OutlineSimulator {
  /// The displayed children of every loaded parent; `nil` is the root level.
  var displayed: [String?: [String]] = [:]
  var loaded: Set<String>

  init(tree: OutlineTree<TestItem>, loaded: Set<String>) {
    self.loaded = loaded.filter { id in
      tree.contains(id) && tree.ancestors(of: id).allSatisfy(loaded.contains)
    }
    load(nil, from: tree)
  }

  private mutating func load(_ parent: String?, from tree: OutlineTree<TestItem>) {
    displayed[parent] = tree.children(of: parent)
    for child in tree.children(of: parent) where loaded.contains(child) {
      load(child, from: tree)
    }
  }

  /// Applies the changes; returns `false` if one of them is invalid for the displayed state.
  mutating func apply(_ changes: [OutlineChange<String>]) -> Bool {
    for change in changes {
      switch change {
      case .remove(let parent, let index):
        guard var children = displayed[parent], children.indices.contains(index) else {
          return false
        }
        drop(children.remove(at: index))
        displayed[parent] = children
      case .insert(let id, let parent, let index):
        guard var children = displayed[parent], (0...children.count).contains(index),
          !isDisplayed(id)
        else { return false }
        children.insert(id, at: index)
        displayed[parent] = children
        // A freshly inserted element starts collapsed.
        loaded.remove(id)
      case .move(let id, let fromParent, let fromIndex, let toParent, let toIndex):
        guard var source = displayed[fromParent], source.indices.contains(fromIndex),
          source[fromIndex] == id
        else { return false }
        source.remove(at: fromIndex)
        displayed[fromParent] = source
        guard var target = displayed[toParent], (0...target.count).contains(toIndex) else {
          return false
        }
        target.insert(id, at: toIndex)
        displayed[toParent] = target
      case .reload(let id):
        guard isDisplayed(id) else { return false }
      }
    }
    return true
  }

  private mutating func drop(_ id: String) {
    loaded.remove(id)
    for child in displayed.removeValue(forKey: id) ?? [] {
      drop(child)
    }
  }

  func isDisplayed(_ id: String) -> Bool {
    displayed.values.contains { $0.contains(id) }
  }

  /// Whether every loaded level shows exactly the new snapshot's children.
  func matches(_ tree: OutlineTree<TestItem>) -> Bool {
    displayed.allSatisfy { parent, children in
      if let parent, !isDisplayed(parent) { return false }
      return children == tree.children(of: parent)
    }
  }
}

@Suite struct OutlineDiffTests {
  private func diff(
    _ old: [TestItem], _ new: [TestItem], loaded: Set<String> = []
  ) -> (changes: [OutlineChange<String>], valid: Bool) {
    let oldTree = OutlineTree(old, children: \.children)
    let newTree = OutlineTree(new, children: \.children)
    let changes = newTree.changes(from: oldTree, loaded: loaded)
    var simulator = OutlineSimulator(tree: oldTree, loaded: loaded)
    let valid = simulator.apply(changes) && simulator.matches(newTree)
    return (changes, valid)
  }

  @Test func reportsNothingForEqualTrees() {
    #expect(diff(sampleRoots, sampleRoots, loaded: ["a", "a2"]).changes.isEmpty)
  }

  @Test func insertsAndRemovesAtTheRootLevel() {
    let inserted = diff([.leaf("x")], [.leaf("x"), .leaf("y")])
    #expect(inserted.changes == [.insert(id: "y", parent: nil, index: 1)])

    let removed = diff([.leaf("x"), .leaf("y")], [.leaf("y")])
    #expect(removed.changes == [.remove(parent: nil, index: 0)])
  }

  @Test func reordersSiblingsWithMoves() {
    let result = diff([.leaf("x"), .leaf("y"), .leaf("z")], [.leaf("z"), .leaf("x"), .leaf("y")])
    #expect(
      result.changes == [.move(id: "z", fromParent: nil, fromIndex: 2, toParent: nil, toIndex: 0)])
    #expect(result.valid)
  }

  @Test func movesBetweenLoadedParentsKeepingTheSubtree() {
    let old: [TestItem] = [.group("a", [.group("f", [.leaf("f1")])]), .group("b")]
    let new: [TestItem] = [.group("a"), .group("b", [.group("f", [.leaf("f1")])])]
    let result = diff(old, new, loaded: ["a", "b", "f"])
    #expect(
      result.changes.first
        == .move(id: "f", fromParent: "a", fromIndex: 0, toParent: "b", toIndex: 0))
    #expect(result.valid)
  }

  @Test func onlyReloadsCollapsedParents() {
    // b is collapsed, so adding a child to it only refreshes its row.
    let result = diff([.group("b", [.leaf("x")])], [.group("b", [.leaf("x"), .leaf("y")])])
    #expect(result.changes == [.reload("b")])
  }

  @Test func removesElementsMovedIntoCollapsedParents() {
    let result = diff([.leaf("x"), .group("b")], [.group("b", [.leaf("x")])])
    #expect(result.changes == [.remove(parent: nil, index: 0), .reload("b")])
    #expect(result.valid)
  }

  @Test func insertsElementsMovedOutOfCollapsedParents() {
    let result = diff([.group("b", [.leaf("x")])], [.group("b"), .leaf("x")])
    #expect(result.changes == [.insert(id: "x", parent: nil, index: 1), .reload("b")])
    #expect(result.valid)
  }

  @Test func reloadsLoadedParentsWhoseDisclosureChanges() {
    let result = diff([.group("b", [.leaf("x")])], [.group("b")], loaded: ["b"])
    #expect(result.changes == [.remove(parent: "b", index: 0), .reload("b")])
    #expect(result.valid)
  }

  @Test func rescuesSurvivorsOfRemovedSubtrees() {
    // a disappears, but its child a1 moves to the root level.
    let old: [TestItem] = [.group("a", [.leaf("a1")]), .leaf("c")]
    let new: [TestItem] = [.leaf("a1"), .leaf("c")]
    let result = diff(old, new, loaded: ["a"])
    #expect(result.valid)
  }

  @Test func swapsParentAndChild() {
    let old: [TestItem] = [.group("a", [.group("b", [.leaf("x")])])]
    let new: [TestItem] = [.group("b", [.group("a", [.leaf("x")])])]
    #expect(diff(old, new, loaded: ["a", "b"]).valid)
  }

  @Test func ignoresLoadedStateBelowCollapsedAncestors() {
    // a2 is expanded, but a is collapsed, so neither a2's children nor a2 itself are displayed.
    // a's own children are unchanged, so the outline needs no update at all.
    var new = sampleRoots
    new[0].children?[1].children?.append(.leaf("a2y"))
    let result = diff(sampleRoots, new, loaded: ["a2"])
    #expect(result.changes.isEmpty)
  }

  @Test(arguments: 0..<500)
  func producesValidChangesForRandomEdits(seed: Int) {
    var random = SeededRandom(seed: UInt64(seed))
    let old = RandomTree.make(using: &random)
    let new = RandomTree.edit(old, using: &random)
    let oldTree = OutlineTree(old, children: \.children)
    let loaded = Set(
      RandomTree.allIDs(old).filter { oldTree.isExpandable($0) && random.next() % 3 != 0 })

    let result = diff(old, new, loaded: loaded)
    #expect(result.valid, "seed \(seed)")
  }
}

// MARK: - Random trees

/// A small, deterministic pseudo-random generator (SplitMix64) so failures are reproducible.
struct SeededRandom: RandomNumberGenerator {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed &+ 0x9E37_79B9_7F4A_7C15
  }

  mutating func next() -> UInt64 {
    state &+= 0x9E37_79B9_7F4A_7C15
    var value = state
    value = (value ^ (value >> 30)) &* 0xBF58_476D_1CE4_E5B9
    value = (value ^ (value >> 27)) &* 0x94D0_49BB_1331_11EB
    return value ^ (value >> 31)
  }
}

enum RandomTree {
  static func make(using random: inout SeededRandom) -> [TestItem] {
    var counter = 0
    func level(_ depth: Int) -> [TestItem] {
      (0..<Int.random(in: 0...4, using: &random)).map { _ in
        counter += 1
        let id = "n\(counter)"
        if depth < 3, Bool.random(using: &random) {
          return .group(id, level(depth + 1))
        }
        return .leaf(id)
      }
    }
    return level(0)
  }

  static func allIDs(_ items: [TestItem]) -> [String] {
    items.flatMap { [$0.id] + allIDs($0.children ?? []) }
  }

  /// Applies a few random removals, insertions, reorders and moves between groups.
  static func edit(_ roots: [TestItem], using random: inout SeededRandom) -> [TestItem] {
    var roots = roots
    var nextID = 1000
    for _ in 0..<Int.random(in: 1...6, using: &random) {
      let ids = allIDs(roots)
      switch Int.random(in: 0..<4, using: &random) {
      case 0 where !ids.isEmpty:
        if let id = ids.randomElement(using: &random) { _ = remove(id, from: &roots) }
      case 1:
        nextID += 1
        let groups = [nil] + groupIDs(roots).map(Optional.some)
        insert(
          .leaf("new\(nextID)"), into: groups.randomElement(using: &random) ?? nil, in: &roots,
          using: &random)
      case 2 where !ids.isEmpty:
        // Move an element into a random group or the root, avoiding cycles.
        guard let id = ids.randomElement(using: &random),
          let item = remove(id, from: &roots)
        else { break }
        let groups = [nil] + groupIDs(roots).map(Optional.some)
        insert(item, into: groups.randomElement(using: &random) ?? nil, in: &roots, using: &random)
      default:
        roots.shuffle(using: &random)
      }
    }
    return roots
  }

  private static func groupIDs(_ items: [TestItem]) -> [String] {
    items.flatMap { item in
      (item.children != nil ? [item.id] : []) + groupIDs(item.children ?? [])
    }
  }

  private static func remove(_ id: String, from items: inout [TestItem]) -> TestItem? {
    if let index = items.firstIndex(where: { $0.id == id }) {
      return items.remove(at: index)
    }
    for index in items.indices {
      guard var children = items[index].children,
        let removed = remove(id, from: &children)
      else { continue }
      items[index].children = children
      return removed
    }
    return nil
  }

  private static func insert(
    _ item: TestItem, into group: String?, in items: inout [TestItem],
    using random: inout SeededRandom
  ) {
    guard let group else {
      items.insert(item, at: Int.random(in: 0...items.count, using: &random))
      return
    }
    for index in items.indices {
      if items[index].id == group {
        var children = items[index].children ?? []
        children.insert(item, at: Int.random(in: 0...children.count, using: &random))
        items[index].children = children
        return
      }
      if var children = items[index].children {
        insert(item, into: group, in: &children, using: &random)
        items[index].children = children
      }
    }
  }
}
