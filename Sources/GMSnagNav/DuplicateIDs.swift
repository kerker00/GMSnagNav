import OSLog
import SwiftUI

extension SnagOutline {
  /// Reports identifiers that occur more than once in the outline's data.
  ///
  /// Identifiers must be unique across the whole tree, not only among siblings. When one repeats,
  /// the outline keeps its first occurrence in depth-first order and leaves out every later
  /// occurrence together with its subtree, so the rows the user sees no longer match the data.
  ///
  /// `handler` receives all repeated identifiers of the current data whenever they change, not on
  /// every update, and not at all while the data is free of repeats. Without a handler, the
  /// outline stops at an assertion in debug builds. Either way, it logs an error to the unified
  /// logging system under the subsystem `GMSnagNav`.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter handler: Receives the identifiers that occur more than once.
  public func onOutlineDuplicateIDs(_ handler: @escaping (Set<ID>) -> Void) -> Self {
    var copy = self
    copy.behavior.duplicateIDs = handler
    return copy
  }
}

extension OutlineBehavior {
  /// Reports repeated identifiers in `tree` unless `previous` had the same ones, so a host sees
  /// each mistake once instead of on every update.
  func reportDuplicateIDs(in tree: OutlineTree<Element>, previous: OutlineTree<Element>) {
    let duplicates = tree.duplicateIDs
    guard !duplicates.isEmpty, duplicates != previous.duplicateIDs else { return }

    let description = duplicates.map { String(describing: $0) }.sorted().joined(separator: ", ")
    diagnosticsLogger.error(
      "\(duplicates.count, privacy: .public) identifiers occur more than once; only their first occurrence is shown: \(description)"
    )
    if let duplicateIDs {
      duplicateIDs(duplicates)
    } else {
      assertionFailure(
        "SnagOutline identifiers must be unique across the whole tree. Repeated: \(description). "
          + "Use onOutlineDuplicateIDs(_:) to handle repeats without this assertion.")
    }
  }
}

private let diagnosticsLogger = Logger(subsystem: "GMSnagNav", category: "Outline")
