import GMSnagNav
import SwiftUI

/// The library sidebar, built with `SnagOutline`.
///
/// Selection and expansion are plain bindings owned by the app: the toolbar's expand and collapse
/// buttons and the "reveal new item" behavior simply change the `expansion` set.
struct SidebarView: View {
  @Environment(Library.self) private var library
  @Binding var selection: LibraryItem.ID?
  let onError: (Error) -> Void

  @State private var expansion: Set<LibraryItem.ID> = []
  @State private var openedDocument: String?
  @AppStorage("foldersSelectable") private var foldersSelectable = true
  @AppStorage("outlineStyle") private var style = DemoOutlineStyle.automatic
  @AppStorage("indentationStep") private var indentationStep = IndentationStep.regular
  @AppStorage("largeRows") private var largeRows = false

  var body: some View {
    outline
      .onAppear {
        // Start with the top-level folders open.
        expansion = Set(library.roots.filter(\.isFolder).map(\.id))
      }
      .onChange(of: foldersSelectable) {
        if !foldersSelectable, let selection, library.item(selection)?.isFolder == true {
          self.selection = nil
        }
      }
      .toolbar {
        ToolbarItemGroup {
          Menu {
            Button("Expand All", systemImage: "arrow.down.right.and.arrow.up.left") {
              expansion = Set(library.allFolders.map(\.item.id))
            }
            Button("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right") {
              expansion = []
            }
            Divider()
            Toggle("Folders Are Selectable", isOn: $foldersSelectable)
            Divider()
            Picker("Style", selection: $style) {
              ForEach(DemoOutlineStyle.allCases) { Text($0.title).tag($0) }
            }
            Picker("Indentation", selection: $indentationStep) {
              ForEach(IndentationStep.allCases) { Text($0.title).tag($0) }
            }
            #if os(macOS)
              Toggle("Large Rows (AppKit)", isOn: $largeRows)
            #endif
          } label: {
            Label("Outline", systemImage: "list.bullet.indent")
          }

          Menu {
            Button("New Folder", systemImage: "folder.badge.plus") { add(.folder("New Folder")) }
            Button("New Document", systemImage: "doc.badge.plus") {
              add(.document("New Document"))
            }
          } label: {
            Label("Add", systemImage: "plus")
          }
        }
      }
      .alert(
        "Opened \"\(openedDocument ?? "")\"",
        isPresented: Binding(
          get: { openedDocument != nil },
          set: { if !$0 { openedDocument = nil } })
      ) {
        Button("OK", role: .cancel) {}
      } message: {
        Text("A real app would open the document here.")
      }
      .safeAreaInset(edge: .bottom) {
        Text("GMSnagNav \(GMSnagNav.version)")
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .padding(8)
      }
  }

  private var outline: some View {
    let outline = SnagOutline(
      library.roots, children: \.children, selection: $selection, expansion: $expansion
    ) { item in
      Label(item.name, systemImage: item.systemImage)
        .accessibilityIdentifier("sidebar-row-\(item.name)")
    }
    .outlineSelectable { item in foldersSelectable || !item.isFolder }
    .outlineContextMenu { ids in contextMenu(for: ids) }
    .outlineStyle(style.outlineStyle)
    .outlineIndentation(indentationStep.width)
    .outlineDraggable()
    .onOutlineDrop(validate: library.dropResult(for:), perform: drop)

    #if os(macOS)
      // On iOS a tap already selects and navigates, so the primary action is macOS only.
      return
        outline
        .outlinePrimaryAction(open)
        // The AppKit escape hatch: anything GMSnagNav does not offer as a modifier.
        .outlineAppKitConfiguration { [largeRows] outlineView in
          outlineView.rowSizeStyle = largeRows ? .large : .default
        }
    #else
      return outline
    #endif
  }

  /// The context menu: item actions for one item, bulk delete for several, and adding at the root
  /// level when the menu opens on empty space.
  @ViewBuilder private func contextMenu(for ids: Set<LibraryItem.ID>) -> some View {
    switch ids.count {
    case 0:
      Button("New Folder", systemImage: "folder.badge.plus") {
        selection = library.add(.folder("New Folder"), into: nil)
      }
      Button("New Document", systemImage: "doc.badge.plus") {
        selection = library.add(.document("New Document"), into: nil)
      }
    case 1:
      if let id = ids.first {
        ItemActions(itemID: id, onError: onError)
      }
    default:
      Button("Delete \(ids.count) Items", systemImage: "trash", role: .destructive) {
        ids.forEach(library.delete)
      }
    }
  }

  /// Moves the dropped items and opens the folder they were dropped into, so they stay visible.
  private func drop(
    _ proposal: OutlineDropProposal<LibraryItem.ID>, operation: OutlineDropOperation
  ) -> Bool {
    do {
      try library.performDrop(proposal)
      if let folder = proposal.target.parent {
        expansion.insert(folder)
      }
      return true
    } catch {
      onError(error)
      return false
    }
  }

  /// Double-click: folders toggle their expansion, documents are "opened".
  private func open(_ ids: Set<LibraryItem.ID>) {
    for id in ids {
      guard let item = library.item(id) else { continue }
      if item.isFolder {
        if expansion.contains(id) { expansion.remove(id) } else { expansion.insert(id) }
      } else {
        openedDocument = item.name
      }
    }
  }

  /// Adds the item next to the selection — into the selected folder, or the root level otherwise —
  /// and opens that folder so the new item is visible.
  private func add(_ item: LibraryItem) {
    let folder = selection.flatMap { library.item($0)?.isFolder == true ? $0 : nil }
    if let folder {
      expansion.insert(folder)
    }
    selection = library.add(item, into: folder)
  }
}

/// The styles offered in the demo's Outline menu, storable in `@AppStorage`.
enum DemoOutlineStyle: String, CaseIterable, Identifiable {
  case automatic
  case sidebar
  case plain

  var id: Self { self }

  var title: String {
    switch self {
    case .automatic: "Automatic"
    case .sidebar: "Sidebar"
    case .plain: "Plain"
    }
  }

  var outlineStyle: SnagOutlineStyle {
    switch self {
    case .automatic: .automatic
    case .sidebar: .sidebar
    case .plain: .plain
    }
  }
}

/// The indentation steps offered in the demo's Outline menu, relative to each platform's default.
enum IndentationStep: String, CaseIterable, Identifiable {
  case compact
  case regular
  case wide

  var id: Self { self }

  var title: String {
    switch self {
    case .compact: "Compact"
    case .regular: "Regular"
    case .wide: "Wide"
    }
  }

  var width: CGFloat {
    #if os(macOS)
      let regular: CGFloat = 14
    #else
      let regular: CGFloat = 24
    #endif
    switch self {
    case .compact: return regular * 0.7
    case .regular: return regular
    case .wide: return regular * 1.6
    }
  }
}
