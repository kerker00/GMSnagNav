import SwiftUI

/// A single request to reveal an element or give the outline keyboard focus.
///
/// Store an optional request in `@State` and pass its binding to `outlineNavigation(_:onCompletion:)`.
/// Create a new request for every action, even when revealing the same identifier again.
public struct OutlineNavigationRequest<ID: Hashable & Sendable>: Identifiable, Equatable, Sendable {
  /// Identifies this individual action, independently of its target element.
  public let id: UUID
  /// The element to reveal, or `nil` for a focus-only request.
  public let target: ID?
  /// Whether this request also transfers keyboard focus to the outline.
  public let takesFocus: Bool

  /// Opens the element's ancestors and scrolls its row into view without changing selection.
  ///
  /// - Parameters:
  ///   - id: An identifier in the tree currently provided to the outline.
  ///   - focus: Whether to also transfer keyboard focus to the outline.
  public static func reveal(_ id: ID, focus: Bool = false) -> Self {
    Self(id: UUID(), target: id, takesFocus: focus)
  }

  /// Transfers keyboard focus to the outline, keeping its selection and expansion.
  public static func focus() -> Self {
    Self(id: UUID(), target: nil, takesFocus: true)
  }
}

/// The result of an explicit outline navigation request.
public enum OutlineNavigationResult: Equatable, Sendable {
  /// The row was revealed and any requested keyboard-focus transfer succeeded.
  case completed
  /// The identifier is absent from the current tree, including when filtered out by the host.
  case elementNotFound
  /// The native outline could not display the row, or is not attached to a window.
  case outlineUnavailable
  /// Any requested reveal succeeded, but keyboard focus could not transfer, for example during renaming.
  case focusUnavailable
}

extension SnagOutline {
  /// Handles explicit reveal and keyboard-focus requests without changing the selection binding.
  ///
  /// Requests run after the view update, using the latest tree. The binding is cleared before
  /// `onCompletion` runs. Replacing or clearing a request before execution cancels it silently.
  /// Only one outline should consume a binding. A request waits while that outline is unmounted.
  ///
  /// Unlike automatic selection reveal, this works for an already-selected element and when
  /// `outlineRevealsSelection(false)` is set. Explicit requests take precedence over automatic
  /// selection reveal in the same update. Ancestors are added to the expansion binding.
  /// Missing or filtered-out elements produce `elementNotFound`; the package never clears a
  /// host's search. Clear the filter when offering "Show in Sidebar" in your app.
  ///
  /// Focus requests preserve inline renaming and report `focusUnavailable` while it is active.
  /// Keyboard focus is separate from VoiceOver focus and split-view column visibility.
  /// Apply this directly to `SnagOutline`, before general view modifiers.
  public func outlineNavigation(
    _ request: Binding<OutlineNavigationRequest<ID>?>,
    onCompletion:
      @escaping @MainActor (OutlineNavigationRequest<ID>, OutlineNavigationResult) -> Void = {
        _, _ in
      }
  ) -> Self {
    var copy = self
    copy.behavior.navigation = OutlineNavigationHandler(
      request: request, onCompletion: onCompletion)
    return copy
  }
}

struct OutlineNavigationHandler<ID: Hashable & Sendable> {
  let request: Binding<OutlineNavigationRequest<ID>?>
  let onCompletion: @MainActor (OutlineNavigationRequest<ID>, OutlineNavigationResult) -> Void
}

/// Coalesces view updates and defers binding writes until SwiftUI has finished updating.
@MainActor
final class OutlineNavigationDriver<ID: Hashable & Sendable> {
  private var scheduled: UUID?
  private var task: Task<Void, Never>?

  func settled() async { await task?.value }

  func update(
    _ handler: OutlineNavigationHandler<ID>?,
    perform: @escaping @MainActor (OutlineNavigationRequest<ID>) -> OutlineNavigationResult
  ) {
    guard let handler, let request = handler.request.wrappedValue else {
      task?.cancel()
      scheduled = nil
      return
    }
    guard scheduled != request.id else { return }
    task?.cancel()
    scheduled = request.id
    task = Task { @MainActor [weak self] in
      guard !Task.isCancelled, let self, self.scheduled == request.id,
        handler.request.wrappedValue?.id == request.id
      else { return }
      let result = perform(request)
      if handler.request.wrappedValue?.id == request.id { handler.request.wrappedValue = nil }
      handler.onCompletion(request, result)
    }
  }
}
