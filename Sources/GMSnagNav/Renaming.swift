import SwiftUI

extension SnagOutline {
  /// Lets the user rename elements in place, in a text field within their row.
  ///
  /// Renaming starts when `renaming` is set to an element's identifier — for example from a
  /// "Rename" context menu item — and, on macOS, when the user presses Return while exactly one
  /// renamable row is selected, as in the Finder. Double-click then remains the way to run the
  /// primary action. The outline sets `renaming` back to `nil` when renaming ends.
  ///
  /// The row shows a text field with its current name selected. Return commits the new name,
  /// Escape cancels, and moving the focus elsewhere commits as well. `onRename` receives only names
  /// that differ from the current one; validate and store them in your model.
  ///
  /// ```swift
  /// .outlineRenaming($renamingID) { id, name in
  ///   library.rename(id, to: name)
  /// }
  /// ```
  ///
  /// ``OutlineLabel`` and section headers turn into the text field by themselves. In rows with
  /// other content, show the name with ``OutlineRenamableText``.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameters:
  ///   - renaming: The identifier of the element being renamed, or `nil`.
  ///   - canRename: Returns whether an element can be renamed. All elements can by default.
  ///   - onRename: Receives the identifier and the new name when the user commits a change.
  public func outlineRenaming(
    _ renaming: Binding<ID?>,
    canRename: @escaping (Element) -> Bool = { _ in true },
    onRename: @escaping (ID, String) -> Void
  ) -> Self {
    var copy = self
    copy.behavior.renaming = OutlineRenameHandler(
      renaming: renaming, canRename: canRename, onRename: onRename)
    return copy
  }
}

/// The host's renaming state and callbacks.
struct OutlineRenameHandler<Element: Identifiable> where Element.ID: Sendable {
  let renaming: Binding<Element.ID?>
  let canRename: (Element) -> Bool
  let onRename: (Element.ID, String) -> Void
}

extension OutlineBehavior {
  /// The rename session for a row, or `nil` unless that row is being renamed.
  ///
  /// - Parameter returnFocus: Called when the user ends renaming with the keyboard, so the
  ///   outline can take the keyboard focus back from the disappearing text field.
  func renameSession(
    for id: Element.ID, in tree: OutlineTree<Element>, returnFocus: @escaping () -> Void = {}
  ) -> OutlineRenameSession? {
    guard let renaming, renaming.renaming.wrappedValue == id, let element = tree.element(id),
      renaming.canRename(element)
    else { return nil }
    return OutlineRenameSession { original, name, returnsFocus in
      if let name, name != original { renaming.onRename(id, name) }
      renaming.renaming.wrappedValue = nil
      if returnsFocus { returnFocus() }
    }
  }

  /// Starts renaming `id` if the host allows it; returns whether renaming started.
  func startRenaming(_ id: Element.ID, in tree: OutlineTree<Element>) -> Bool {
    guard let renaming, let element = tree.element(id), renaming.canRename(element) else {
      return false
    }
    renaming.renaming.wrappedValue = id
    return true
  }
}

/// Ends the renaming of one row; rows read it from the environment.
struct OutlineRenameSession {
  /// Ends renaming. `original` is the name the row showed before, `name` the typed name to keep,
  /// or `nil` to cancel. `returnsFocus` is `true` when the user ended renaming with the keyboard
  /// rather than by moving the focus elsewhere.
  let end: (_ original: String, _ name: String?, _ returnsFocus: Bool) -> Void
}

extension EnvironmentValues {
  /// Set for the row that is being renamed.
  @Entry var outlineRenameSession: OutlineRenameSession?
}

/// A row's name that turns into a text field while the row is being renamed.
///
/// ``OutlineLabel`` uses it for its title. Use it in custom rows of an outline that supports
/// renaming with `outlineRenaming(_:canRename:onRename:)`:
///
/// ```swift
/// HStack {
///   Image(systemName: item.systemImage)
///   OutlineRenamableText(item.name)
///   Spacer()
///   Text(item.count, format: .number)
/// }
/// ```
///
/// Outside a renaming row it shows the name like `Text`, in a single line.
public struct OutlineRenamableText: View {
  private let title: String
  @Environment(\.outlineRenameSession) private var session

  /// Creates the text for a row's name.
  public init(_ title: String) {
    self.title = title
  }

  /// The content of the text.
  public var body: some View {
    if let session {
      OutlineRenameField(title: title, session: session)
    } else {
      Text(title)
        .lineLimit(1)
    }
  }
}

/// The text field of a row being renamed: focused, with its whole text selected.
private struct OutlineRenameField: View {
  let title: String
  let session: OutlineRenameSession

  @State private var name: String
  @State private var selection: TextSelection?
  @FocusState private var isFocused: Bool
  @State private var hasEnded = false

  init(title: String, session: OutlineRenameSession) {
    self.title = title
    self.session = session
    _name = State(initialValue: title)
  }

  var body: some View {
    TextField(text: $name, selection: $selection) {
      Text("Name", bundle: .module)
    }
    .labelsHidden()
    .textFieldStyle(.plain)
    .focused($isFocused)
    .onSubmit { end(commit: true, returnsFocus: true) }
    #if os(macOS)
      .onExitCommand { end(commit: false, returnsFocus: true) }
    #endif
    .onChange(of: isFocused) {
      // Clicking elsewhere ends renaming and keeps the new name, as in the Finder; the focus
      // stays where the user moved it.
      if !isFocused { end(commit: true, returnsFocus: false) }
    }
    .onAppear {
      selection = TextSelection(range: name.startIndex..<name.endIndex)
      isFocused = true
    }
  }

  private func end(commit: Bool, returnsFocus: Bool) {
    guard !hasEnded else { return }
    hasEnded = true
    session.end(title, commit ? name : nil, returnsFocus)
  }
}
