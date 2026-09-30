import SwiftUI

/// The sidebar's actions, published to the menu bar while its window is active.
struct SidebarActions {
  let newFolder: () -> Void
  let newDocument: () -> Void
  /// Deletes the selected item, or `nil` while nothing is selected.
  let deleteSelection: (() -> Void)?
  let expandAll: () -> Void
  let collapseAll: () -> Void
}

extension FocusedValues {
  @Entry var sidebarActions: SidebarActions?
}

/// Menu bar commands for everything the sidebar offers in its bars and menus, since every toolbar
/// and bottom bar item should also be available as a menu command.
struct DemoCommands: Commands {
  @FocusedValue(\.sidebarActions) private var actions
  @AppStorage("foldersSelectable") private var foldersSelectable = true
  @AppStorage("outlineStyle") private var style = DemoOutlineStyle.automatic
  @AppStorage("indentationStep") private var indentationStep = IndentationStep.regular
  @AppStorage("largeRows") private var largeRows = false

  var body: some Commands {
    // "Show Sidebar" and "Hide Sidebar" in the View menu.
    SidebarCommands()

    CommandGroup(after: .newItem) {
      Button("New Folder") { actions?.newFolder() }
        .keyboardShortcut("n", modifiers: [.command, .shift])
        .disabled(actions == nil)
      Button("New Document") { actions?.newDocument() }
        .keyboardShortcut("n", modifiers: [.command, .option])
        .disabled(actions == nil)
    }

    CommandGroup(after: .pasteboard) {
      // No Command-Delete: in the name field it deletes to the start of the line.
      Button("Delete Item") { actions?.deleteSelection?() }
        .disabled(actions?.deleteSelection == nil)
    }

    CommandGroup(after: .sidebar) {
      Button("Expand All") { actions?.expandAll() }
        .disabled(actions == nil)
      Button("Collapse All") { actions?.collapseAll() }
        .disabled(actions == nil)
      Divider()
      Toggle("Folders Are Selectable", isOn: $foldersSelectable)
      Picker("Outline Style", selection: $style) {
        ForEach(DemoOutlineStyle.allCases) { Text($0.title).tag($0) }
      }
      Picker("Indentation", selection: $indentationStep) {
        ForEach(IndentationStep.allCases) { Text($0.title).tag($0) }
      }
      #if os(macOS)
        Toggle("Large Rows (AppKit)", isOn: $largeRows)
      #endif
      Divider()
    }
  }
}
