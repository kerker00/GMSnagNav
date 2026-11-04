/// One step that updates an outline view from an old snapshot towards a new one.
///
/// Indices refer to the children of `parent` (`nil` for the root level) at the moment the step
/// is applied, exactly like `NSOutlineView`'s `removeItems`, `insertItems` and `moveItem` expect.
enum OutlineChange<ID: Hashable>: Equatable {
  /// Removes the child at `index` of `parent`, together with its subtree.
  case remove(parent: ID?, index: Int)
  /// Inserts `id` as the child at `index` of `parent`.
  case insert(id: ID, parent: ID?, index: Int)
  /// Moves the child at `fromIndex` of `fromParent` to `toIndex` of `toParent`, keeping its
  /// subtree. `toIndex` refers to the destination's children after the item has been taken out.
  case move(id: ID, fromParent: ID?, fromIndex: Int, toParent: ID?, toIndex: Int)
  /// Refreshes an item whose children changed while they are not displayed, so its disclosure
  /// triangle and child count are current.
  case reload(ID)
}

extension OutlineTree {
  /// Computes the steps that turn the displayed part of `old` into the displayed part of `self`.
  ///
  /// An outline view only knows the children of *loaded* parents: the root level and every
  /// expanded element whose ancestors are all expanded. Only those levels are diffed; changes
  /// below collapsed elements need no more than a ``OutlineChange/reload(_:)`` of that element.
  /// Elements that move keep their identity and subtree through ``OutlineChange/move``.
  ///
  /// - Parameters:
  ///   - old: The snapshot the outline view currently displays.
  ///   - loaded: The elements whose children the outline view currently displays; the root level
  ///     is always loaded and need not be included.
  /// - Returns: The steps in the order they must be applied.
  func changes(from old: OutlineTree<Element>, loaded: Set<ID>) -> [OutlineChange<ID>] {
    var diff = DiffState(old: old, new: self, loaded: loaded)
    diff.removeElementsThatLeaveTheDisplay()
    diff.placeDisplayedChildren()
    diff.reloadChangedCollapsedElements()
    return diff.changes
  }
}

/// The working state of a diff: a simulation of what the outline view displays.
private struct DiffState<Element: Identifiable> {
  typealias ID = Element.ID

  let old: OutlineTree<Element>
  let new: OutlineTree<Element>
  var oldLoaded: Set<ID> = []

  /// The displayed children of every loaded parent; the key `nil` is the root level.
  var displayed: [ID?: [ID]] = [:]
  /// The loaded parent of every displayed element.
  var parentOf: [ID: ID?] = [:]
  /// Elements that stay loaded — their displayed children are placed — in the new snapshot.
  var newLoaded: Set<ID> = []
  /// Elements inserted by this diff; the outline view loads their children itself on expansion.
  var inserted: Set<ID> = []
  var changes: [OutlineChange<ID>] = []

  init(old: OutlineTree<Element>, new: OutlineTree<Element>, loaded: Set<ID>) {
    self.old = old
    self.new = new
    load(loaded)
  }

  /// Visits only loaded levels, so every reached child's ancestors are already known to be loaded.
  private mutating func load(_ loaded: Set<ID>) {
    var pending: [ID?] = [nil]
    while let parent = pending.popLast() {
      let children = old.children(of: parent)
      displayed[parent] = children
      for child in children {
        parentOf[child] = parent
        if loaded.contains(child) {
          oldLoaded.insert(child)
          pending.append(child)
        }
      }
    }
  }

  // MARK: Removal

  /// Retains loaded parents only while their old and new ancestor levels both stay loaded.
  private func survivingLoadedParents() -> Set<ID> {
    var result = oldLoaded.filter { new.contains($0) && parentOf[$0] != nil }
    var pending = Array(
      result.filter { id in
        (old.parent(of: id).map { !result.contains($0) } ?? false)
          || (new.parent(of: id).map { !result.contains($0) } ?? false)
      })
    while let id = pending.popLast() {
      guard result.remove(id) != nil else { continue }
      // Losing an old ancestor removes its native subtree. Rescued rows are reinserted
      // collapsed, so their new descendants must leave the display too.
      pending.append(contentsOf: old.children(of: id))
      pending.append(contentsOf: new.children(of: id))
    }
    return result
  }

  /// Removes displayed elements that no longer exist or whose new parent is not loaded.
  ///
  /// Only the topmost such element of a subtree is removed; its displayed descendants disappear
  /// with it. Descendants that survive elsewhere are inserted again later.
  mutating func removeElementsThatLeaveTheDisplay() {
    var removals: [(parent: ID?, index: Int, id: ID)] = []
    let loaded = survivingLoadedParents()
    var pending: [(parent: ID?, index: Int)] = [(nil, 0)]
    while let top = pending.indices.last {
      let (parent, index) = pending[top]
      let children = displayed[parent] ?? []
      guard index < children.count else {
        pending.removeLast()
        continue
      }
      pending[top].index += 1
      let id = children[index]
      let survives = new.contains(id) && (new.parent(of: id).map(loaded.contains) ?? true)
      if survives {
        if displayed[id] != nil { pending.append((id, 0)) }
      } else {
        removals.append((parent, index, id))
      }
    }

    // Remove from the back of each level so earlier indices stay valid.
    for removal in removals.sorted(by: { $0.index > $1.index }) {
      changes.append(.remove(parent: removal.parent, index: removal.index))
      displayed[removal.parent]?.remove(at: removal.index)
      forget(removal.id)
    }

    // Removing an old ancestor can also forget a parent that survives in a new location. Its
    // newly inserted row starts collapsed, so recompute reachability after forgetting subtrees.
    newLoaded = survivingLoadedParents()
  }

  /// Drops an element and its displayed subtree from the simulation.
  private mutating func forget(_ id: ID) {
    var pending = [id]
    while let child = pending.popLast() {
      parentOf[child] = nil
      pending.append(contentsOf: displayed.removeValue(forKey: child) ?? [])
    }
  }

  // MARK: Placement

  /// Moves and inserts elements so every loaded level matches the new snapshot, top-down.
  mutating func placeDisplayedChildren() {
    // Read through an index instead of removing from the front, which would shift the remaining
    // levels each time and make large outlines quadratic.
    var pending: [ID?] = [nil]
    var next = 0
    while next < pending.count {
      let parent = pending[next]
      next += 1
      let target = new.children(of: parent)
      for (index, id) in target.enumerated() {
        place(id, in: parent, at: index)
        if newLoaded.contains(id) { pending.append(id) }
      }
    }
  }

  private mutating func place(_ id: ID, in parent: ID?, at index: Int) {
    let current = displayed[parent] ?? []
    if index < current.count, current[index] == id { return }

    if let fromParent = parentOf[id], let fromIndex = displayed[fromParent]?.firstIndex(of: id) {
      changes.append(
        .move(
          id: id, fromParent: fromParent, fromIndex: fromIndex, toParent: parent, toIndex: index))
      displayed[fromParent]?.remove(at: fromIndex)
    } else {
      changes.append(.insert(id: id, parent: parent, index: index))
      inserted.insert(id)
    }
    displayed[parent, default: []].insert(id, at: index)
    parentOf[id] = parent
  }

  // MARK: Reloads

  /// Reloads displayed elements whose children changed where the outline view cannot see it.
  mutating func reloadChangedCollapsedElements() {
    var reloads = Set(
      parentOf.keys.filter { id in
        guard !inserted.contains(id) else { return false }
        let before = old.children(of: id)
        let after = new.children(of: id)
        guard before != after else { return false }
        // Loaded levels were updated above; they only need a reload when the disclosure triangle
        // appears or disappears.
        return !newLoaded.contains(id) || before.isEmpty != after.isEmpty
      })
    guard !reloads.isEmpty else { return }
    // Pre-order is the same order as lexicographically sorted index paths, without allocating
    // and comparing a depth-sized path for every reload in a long chain.
    var pending = Array(new.roots.reversed())
    while let id = pending.popLast() {
      if reloads.remove(id) != nil { changes.append(.reload(id)) }
      if reloads.isEmpty { return }
      pending.append(contentsOf: new.children(of: id).reversed())
    }
  }
}
