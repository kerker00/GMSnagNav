/// An immutable, indexed snapshot of a host-provided tree.
///
/// The host owns its data; `OutlineTree` only records the structure it saw at one point in time
/// so that lookups by identifier — parent, position, depth, ancestors — are constant time or
/// proportional to the depth of the tree. Every UI update builds a fresh snapshot.
///
/// Identifiers must be unique across the whole tree. When an identifier appears more than once,
/// only its first occurrence (in depth-first, pre-order) is kept, its later occurrences and their
/// subtrees are skipped, and the identifier is reported in ``duplicateIDs``. Skipping repeats also
/// guarantees termination for children providers that accidentally form a cycle.
struct OutlineTree<Element: Identifiable> {
  typealias ID = Element.ID

  /// The indexed information about a single element of the tree.
  struct Node {
    /// The element as provided by the host.
    let element: Element
    /// The identifier of the parent element, or `nil` for a root element.
    let parent: ID?
    /// The position of the element among its siblings.
    let index: Int
    /// The distance from the root level; root elements have a depth of `0`.
    let depth: Int
    /// The identifiers of the children, or `nil` if the element is a leaf.
    ///
    /// An empty array describes a container without children, such as an empty folder, which
    /// stays expandable. `nil` describes an element that can never have children.
    fileprivate(set) var children: [ID]?
  }

  /// The identifiers of the root elements, in order.
  let roots: [ID]

  /// Identifiers that occurred more than once; only their first occurrence is part of the tree.
  let duplicateIDs: Set<ID>

  private let nodes: [ID: Node]

  /// Creates a snapshot by walking the children of every element.
  ///
  /// - Parameters:
  ///   - roots: The elements at the root level.
  ///   - children: Returns the children of an element, or `nil` if the element is a leaf.
  init<Data: Sequence>(_ roots: Data, children: (Element) -> [Element]?)
  where Data.Element == Element {
    let result = Self.index(Array(roots), children: children)
    self.roots = result.roots
    self.nodes = result.nodes
    self.duplicateIDs = result.duplicateIDs
  }

  /// Creates a snapshot whose children are read through a key path.
  init<Data: Sequence>(_ roots: Data, children: KeyPath<Element, [Element]?>)
  where Data.Element == Element {
    self.init(roots, children: { $0[keyPath: children] })
  }

  /// The number of elements in the tree.
  var count: Int { nodes.count }

  /// Returns whether the tree contains an element with the given identifier.
  func contains(_ id: ID) -> Bool { nodes[id] != nil }

  /// Returns the indexed node for an identifier.
  func node(_ id: ID) -> Node? { nodes[id] }

  /// Returns the element for an identifier.
  func element(_ id: ID) -> Element? { nodes[id]?.element }

  /// Returns the identifier of the parent, or `nil` for root elements and unknown identifiers.
  func parent(of id: ID) -> ID? { nodes[id]?.parent }

  /// Returns the identifiers of the children of `parent`, or of the root level for `nil`.
  ///
  /// Leaves and unknown identifiers have no children and return an empty array.
  func children(of parent: ID?) -> [ID] {
    guard let parent else { return roots }
    return nodes[parent]?.children ?? []
  }

  /// Returns whether the element can have children, even if it currently has none.
  func isExpandable(_ id: ID) -> Bool { nodes[id]?.children != nil }

  /// Returns the identifiers of all ancestors, starting with the parent and ending at the root.
  func ancestors(of id: ID) -> [ID] {
    var result: [ID] = []
    var current = nodes[id]?.parent
    while let ancestor = current {
      result.append(ancestor)
      current = nodes[ancestor]?.parent
    }
    return result
  }

  /// Returns whether `id` lies strictly inside the subtree of `ancestor`.
  ///
  /// An element is not considered its own descendant.
  func isDescendant(_ id: ID, of ancestor: ID) -> Bool {
    var current = nodes[id]?.parent
    while let candidate = current {
      if candidate == ancestor { return true }
      current = nodes[candidate]?.parent
    }
    return false
  }
}

extension OutlineTree {
  /// The level currently being walked: the children of one parent.
  private struct Level {
    let parent: ID?
    let depth: Int
    let elements: [Element]
    var position = 0
    var kept: [ID] = []
  }

  /// Walks the tree depth-first in pre-order.
  ///
  /// The walk uses an explicit stack instead of recursion, so arbitrarily deep host trees cannot
  /// overflow the call stack.
  private static func index(
    _ roots: [Element], children: (Element) -> [Element]?
  ) -> (roots: [ID], nodes: [ID: Node], duplicateIDs: Set<ID>) {
    var nodes: [ID: Node] = [:]
    var duplicateIDs: Set<ID> = []
    var rootIDs: [ID] = []
    var stack = [Level(parent: nil, depth: 0, elements: roots)]

    while let top = stack.indices.last {
      guard stack[top].position < stack[top].elements.count else {
        // The level is complete: attach the kept identifiers to their parent.
        let level = stack.removeLast()
        if let parent = level.parent {
          nodes[parent]?.children = level.kept
        } else {
          rootIDs = level.kept
        }
        continue
      }

      let element = stack[top].elements[stack[top].position]
      stack[top].position += 1
      let id = element.id
      guard nodes[id] == nil else {
        duplicateIDs.insert(id)
        continue
      }

      let depth = stack[top].depth
      // Reserve the identifier before descending so repeats inside the subtree are detected.
      // Leaves keep `children == nil`; containers get their children once their level completes.
      nodes[id] = Node(
        element: element, parent: stack[top].parent, index: stack[top].kept.count, depth: depth,
        children: nil)
      stack[top].kept.append(id)

      if let childElements = children(element) {
        stack.append(Level(parent: id, depth: depth + 1, elements: childElements))
      }
    }
    return (rootIDs, nodes, duplicateIDs)
  }
}
