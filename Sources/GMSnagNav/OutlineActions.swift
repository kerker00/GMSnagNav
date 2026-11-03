import SwiftUI

/// The outcome of choosing an explicit outline action.
public enum OutlineActionResult<ID: Hashable & Sendable>: Equatable, Sendable {
  /// The host performed the complete proposal with the requested operation.
  case completed(OutlineDropProposal<ID>, OutlineDropOperation)
  /// A source is missing, pinned, or now contains another captured source.
  case sourceUnavailable
  /// The destination disappeared or is no longer a container.
  case targetUnavailable
  /// The host's current availability policy disables the action.
  case unavailable
  /// The validator rejected the action or changed its advertised operation or destination.
  case rejected
  /// The host's performer returned false.
  case failed
}

/// Builds move and copy menus from live host data, independently of an outline's native view.
///
/// Create this value at the common parent of your sidebar and detail. Its getter must read the
/// current model, rather than a captured array snapshot. No tree, selection or native view is
/// stored. All changes go through the same callbacks as ``SnagOutline/onOutlineDrop(validate:perform:)``.
/// The host is responsible for performing each complete proposal atomically.
@MainActor
public struct OutlineActions<Element: Identifiable> where Element.ID: Sendable {
  /// The host's identifier type, shared by sources, destinations and completion results.
  public typealias ID = Element.ID

  private let data: () -> [Element]
  private let children: (Element) -> [Element]?
  /// The live pin predicate; reuse it with `outlinePinned(_:)`.
  public let isPinned: (Element) -> Bool
  let handler: OutlineDropHandler<ID>

  /// Creates an action source without copying the host's model.
  ///
  /// - Parameters:
  ///   - data: Reads current roots synchronously from the host's in-memory model.
  ///   - children: Reads children; a key path such as `\.children` also works.
  ///   - isPinned: Protects fixed sources. Pinned containers may still receive items.
  ///   - validate: The existing drop validator. Copy menus require an explicit `.copy` answer.
  ///   - perform: Performs the complete proposal once and reports success.
  public init(
    data: @escaping () -> [Element], children: @escaping (Element) -> [Element]?,
    isPinned: @escaping (Element) -> Bool = { _ in false },
    validate: @escaping (OutlineDropProposal<ID>) -> OutlineDropResult<ID> = {
      $0.isDroppingIntoOwnSubtree ? .reject : .accept(.move)
    },
    perform: @escaping (OutlineDropProposal<ID>, OutlineDropOperation) -> Bool
  ) {
    self.data = data
    self.children = children
    self.isPinned = isPinned
    handler = OutlineDropHandler(validate: validate, perform: perform)
  }

  func currentTree() -> OutlineTree<Element> { OutlineTree(data(), children: children) }

  /// Builds hierarchical destination items for a fixed set of source identifiers.
  ///
  /// Compute items in your view's body so observable reads participate in SwiftUI updates.
  /// Every action reads the model and policies again when chosen. Missing or pinned sources
  /// cancel the entire action; the current selection never replaces the captured sources.
  /// Container drops leave insertion policy to the host, including a drop into the current parent.
  ///
  /// - Parameters:
  ///   - sources: Selected identifiers; ancestors subsume their selected descendants.
  ///   - operation: Exactly the requested move or copy, never silently substituted.
  ///   - expanded: Reads this window's expansion when validating and executing.
  ///   - isAvailable: Reads current availability, such as search, rename or window lifetime.
  ///   - rootTitle: Overrides the localized "Top Level" label.
  ///   - locale: Formats built-in labels, including when the host overrides the system locale.
  ///   - onCompletion: Runs once per chosen action, not when building or dismissing a menu.
  ///   - title: Supplies the host's localized name of a destination.
  public func destinationItems(
    for sources: Set<ID>, operation: OutlineDropOperation,
    expanded: @escaping () -> Set<ID> = { [] },
    isAvailable: @escaping () -> Bool = { true }, rootTitle: String? = nil,
    locale: Locale = .current,
    onCompletion: @escaping (OutlineActionResult<ID>) -> Void = { _ in },
    title: (Element) -> String
  ) -> [OutlineMenuItem] {
    let tree = currentTree()
    let captured = tree.normalizedSources(Array(sources))
    let missingSources = sources.isEmpty || !sources.allSatisfy(tree.contains)
    let available = isAvailable()
    let expansion = expanded()
    let preparation = OutlineActionPreparation(
      sources: captured, tree: tree, expanded: expansion, isPinned: isPinned)

    func action(_ label: String, at target: OutlineDropTarget<ID>) -> OutlineMenuItem {
      let enabled: Bool
      if available && !missingSources,
        case .success = handler.resolveAction(
          sources: captured, target: target, operation: operation, tree: tree,
          expanded: expansion, isPinned: isPinned, preparation: preparation)
      {
        enabled = true
      } else {
        enabled = false
      }
      return .action(label, isDisabled: !enabled) {
        guard !missingSources else {
          onCompletion(.sourceUnavailable)
          return
        }
        guard isAvailable() else {
          onCompletion(.unavailable)
          return
        }
        let current = currentTree()
        guard sources.allSatisfy(current.contains),
          current.normalizedSources(captured).count == captured.count
        else {
          onCompletion(.sourceUnavailable)
          return
        }
        // A selected descendant may have left its captured ancestor since the menu opened.
        // Retain every selected ID and normalize against the current relationships.
        let result = handler.resolveAction(
          sources: current.normalizedSources(Array(sources)), target: target,
          operation: operation, tree: current,
          expanded: expanded(), isPinned: isPinned)
        switch result {
        case .success(let proposal):
          onCompletion(
            handler.perform(proposal, operation) ? .completed(proposal, operation) : .failed)
        case .failure(let failure): onCompletion(failure.result())
        }
      }
    }

    // Post-order assembly avoids recursive walking of a deeply nested host tree.
    var pending = Array(tree.roots.reversed())
    var containers: [ID] = []
    while let id = pending.popLast() {
      guard tree.isExpandable(id) else { continue }
      containers.append(id)
      pending.append(contentsOf: tree.children(of: id).reversed())
    }
    let here = outlineLocalized(operation == .move ? "Move Here" : "Copy Here", locale: locale)
    var built: [ID: OutlineMenuItem] = [:]
    for id in containers.reversed() {
      guard let element = tree.element(id) else { continue }
      let nested = tree.children(of: id).compactMap { built[$0] }
      let name = title(element)
      built[id] =
        nested.isEmpty
        ? action(name, at: .onto(id))
        : .menu(name, children: [action(here, at: .onto(id)), .divider] + nested)
    }
    let roots = tree.roots.compactMap { built[$0] }
    let root = action(
      rootTitle ?? outlineLocalized("Top Level", locale: locale), at: .root)
    return roots.isEmpty ? [root] : [root, .divider] + roots
  }
}

/// Explicitly select the language bundle: String's formatting locale alone does not do so.
func outlineLocalized(_ key: String, locale: Locale) -> String {
  let preferences = [
    locale.identifier.replacingOccurrences(of: "_", with: "-"),
    locale.language.languageCode?.identifier ?? "en",
  ]
  let language =
    Bundle.preferredLocalizations(
      from: Bundle.module.localizations, forPreferences: preferences
    ).first ?? "en"
  let localizedBundle =
    Bundle.module.path(forResource: language, ofType: "lproj")
    .flatMap(Bundle.init(path:)) ?? .module
  return localizedBundle.localizedString(forKey: key, value: nil, table: nil)
}

extension OutlineActionFailure {
  func result<ID: Hashable & Sendable>() -> OutlineActionResult<ID> {
    switch self {
    case .sourceUnavailable: .sourceUnavailable
    case .targetUnavailable: .targetUnavailable
    case .rejected: .rejected
    }
  }
}

extension SnagOutline {
  /// Shares an action source's drop callbacks and live data with this outline.
  ///
  /// Use the same children and pin rules for the outline and the action source. Explicit
  /// hierarchy commands can read live data before execution; pointer drags keep their existing
  /// renderer-snapshot behavior. Apply directly to `SnagOutline`.
  @MainActor public func onOutlineDrop(_ actions: OutlineActions<Element>) -> Self {
    var copy = self
    copy.behavior.drop = actions.handler
    copy.behavior.actionTree = { actions.currentTree() }
    return copy
  }
}
