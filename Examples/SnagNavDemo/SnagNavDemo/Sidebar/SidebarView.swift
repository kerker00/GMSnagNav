import GMSnagNav
import SwiftUI

/// The library sidebar, built with `SnagOutline`.
///
/// Selection and expansion are plain bindings owned by the app: the expand and collapse commands
/// and the "reveal new item" behavior simply change the `expansion` set.
///
/// Searching filters the outline through its children closure, without copying the library, and
/// turns dragging off: positions among the matches say nothing about positions in the library.
///
/// On macOS, the sidebar's actions sit in a bottom bar, following Mario Guzmán's sidebar
/// guidelines: the toolbar above a sidebar keeps only the sidebar toggle. On iOS they stay in the
/// navigation bar, as usual there.
struct SidebarView: View {
  @Environment(Library.self) private var library
  @Binding var selection: LibraryItem.ID?
  let onError: (Error) -> Void

  @State private var expansion: Set<LibraryItem.ID> = []
  @State private var searchText = ""
  /// The expansion while searching, so the user's own expansion survives the search.
  @State private var searchExpansion: Set<LibraryItem.ID> = []
  @State private var didSetInitialExpansion = false
  @State private var openedDocument: String?
  @AppStorage("foldersSelectable") private var foldersSelectable = true
  @AppStorage("outlineStyle") private var style = DemoOutlineStyle.automatic
  @AppStorage("indentationStep") private var indentationStep = IndentationStep.regular
  @AppStorage("largeRows") private var largeRows = false

  var body: some View {
    outline
      .searchable(text: $searchText, placement: .sidebar, prompt: "Search")
      .onChange(of: searchText) {
        // Open every folder on the way to a match; the user may still close them.
        searchExpansion = matchingIDs.filter { library.item($0)?.isFolder == true }
      }
      .overlay {
        if isSearching, matchingIDs.isEmpty {
          ContentUnavailableView.search(text: searchText)
        }
      }
      .focusedSceneValue(\.sidebarActions, actions)
      .onAppear {
        // Start with the top-level folders open — once. On iPhone the sidebar appears again after
        // every navigation back, and must keep the user's expansion then.
        guard !didSetInitialExpansion else { return }
        didSetInitialExpansion = true
        expansion = Set(library.roots.filter(\.isFolder).map(\.id))
      }
      .onChange(of: foldersSelectable) {
        if !foldersSelectable, let selection, library.item(selection)?.isFolder == true {
          self.selection = nil
        }
      }
      #if os(iOS)
        .toolbar {
          ToolbarItemGroup {
            Menu {
              optionsMenuContent
            } label: {
              Label("Outline", systemImage: "list.bullet.indent")
            }
            Menu {
              addMenuContent
            } label: {
              Label("Add", systemImage: "plus")
            }
          }
        }
      #endif
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
      #if os(macOS)
        .safeAreaBar(edge: .bottom, spacing: 0) { bottomBar }
      #else
        .safeAreaInset(edge: .bottom) {
          Text(versionText)
          .font(.footnote)
          .foregroundStyle(.secondary)
          .frame(maxWidth: .infinity)
          .padding(8)
        }
      #endif
  }

  /// The sidebar's actions for the menu bar.
  private var actions: SidebarActions {
    var delete: (() -> Void)?
    if selection != nil {
      delete = { deleteSelection() }
    }
    return SidebarActions(
      newFolder: { newFolder() }, newDocument: { newDocument() }, deleteSelection: delete,
      expandAll: { expandAll() }, collapseAll: { collapseAll() })
  }

  private var versionText: String { "GMSnagNav \(GMSnagNav.version)" }

  /// Expanding, collapsing and the settings the demo offers for the outline.
  @ViewBuilder private var optionsMenuContent: some View {
    Button("Expand All", systemImage: "arrow.down.right.and.arrow.up.left", action: expandAll)
    Button("Collapse All", systemImage: "arrow.up.left.and.arrow.down.right", action: collapseAll)
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
  }

  @ViewBuilder private var addMenuContent: some View {
    Button("New Folder", systemImage: "folder.badge.plus", action: newFolder)
    Button("New Document", systemImage: "doc.badge.plus", action: newDocument)
  }

  #if os(macOS)
    /// The sidebar's bottom bar: 32 points tall with its separator, borderless 31 × 18 point
    /// buttons 1 point apart, 8 points from the edges, and a small secondary label.
    private var bottomBar: some View {
      VStack(spacing: 0) {
        Divider()
        HStack(spacing: 1) {
          Menu {
            addMenuContent
          } label: {
            Image(systemName: "plus")
          }
          .menuStyle(.button)
          .menuIndicator(.hidden)
          .frame(width: 31, height: 18)
          .help("Add a folder or document")
          .accessibilityLabel("Add")

          Button(action: deleteSelection) {
            Image(systemName: "minus")
              .frame(width: 31, height: 18)
          }
          .disabled(selection == nil)
          .help("Delete the selected item")
          .accessibilityLabel("Delete")

          Spacer()
          Text(versionText)
            .font(.caption)
            .foregroundStyle(.secondary)
          Spacer()

          Menu {
            optionsMenuContent
          } label: {
            Image(systemName: "ellipsis.circle")
          }
          .menuStyle(.button)
          .menuIndicator(.hidden)
          .frame(width: 31, height: 18)
          .help("Outline options")
          .accessibilityLabel("Outline Options")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 8)
        .frame(height: 31)
      }
    }
  #endif

  private var isSearching: Bool {
    !searchText.trimmingCharacters(in: .whitespaces).isEmpty
  }

  /// The items whose names match the search, and the folders that lead to them.
  private var matchingIDs: Set<LibraryItem.ID> {
    let query = searchText.trimmingCharacters(in: .whitespaces)
    var result: Set<LibraryItem.ID> = []
    func visit(_ items: [LibraryItem]) -> Bool {
      var found = false
      for item in items {
        let childMatches = visit(item.children ?? [])
        if childMatches || item.name.localizedStandardContains(query) {
          result.insert(item.id)
          found = true
        }
      }
      return found
    }
    _ = visit(library.roots)
    return result
  }

  private var outline: some View {
    let matches = isSearching ? matchingIDs : nil
    let outline = SnagOutline(
      library.roots.filter { matches?.contains($0.id) ?? true },
      children: { item in item.children?.filter { matches?.contains($0.id) ?? true } },
      selection: $selection,
      expansion: isSearching ? $searchExpansion : $expansion
    ) { item in
      OutlineLabel(item.name, systemImage: item.systemImage)
        .accessibilityIdentifier("sidebar-row-\(item.name)")
    }
    .outlineSelectable { item in foldersSelectable || !item.isFolder }
    .outlineContextMenuItems { ids in menuItems(for: ids) }
    .outlineStyle(style.outlineStyle)
    .outlineIndentation(indentationStep.width)
    .outlineDraggable { _ in !isSearching }
    .onOutlineDrop(validate: library.dropResult(for:), perform: drop)

    #if os(macOS)
      // On iOS a tap selects and navigates; also opening documents on every tap would get in
      // the way, so the demo's primary action is macOS only.
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

  /// The context menu: adding, moving and deleting for one item, bulk delete for several, and
  /// adding at the root level when the menu opens on empty space. Adding and deleting are also in
  /// the bottom bar, as the sidebar guidelines ask for commonly used actions.
  ///
  /// Built from items, it shows as a native menu on both platforms; on iOS, UIKit then shares the
  /// long press between the menu and dragging.
  private func menuItems(for ids: Set<LibraryItem.ID>) -> [OutlineMenuItem] {
    switch ids.count {
    case 0:
      return addMenuItems(near: nil)
    case 1:
      guard let id = ids.first else { return [] }
      let destinations: [OutlineMenuItem] =
        [
          .action("Top Level", isDisabled: !library.canMove(id, into: nil)) {
            move(id, into: nil)
          },
          .divider,
        ]
        + library.allFolders.map { folder in
          .action(
            String(repeating: "    ", count: folder.depth) + folder.item.name,
            isDisabled: !library.canMove(id, into: folder.item.id)
          ) { move(id, into: folder.item.id) }
        }
      return addMenuItems(near: id) + [
        .divider,
        .menu("Move to", systemImage: "folder", children: destinations),
        .divider,
        .action("Delete", systemImage: "trash", role: .destructive) { library.delete(id) },
      ]
    default:
      return [
        .action("Delete \(ids.count) Items", systemImage: "trash", role: .destructive) {
          ids.forEach(library.delete)
        }
      ]
    }
  }

  /// "New Folder" and "New Document", adding into `id` if it is a folder, and next to it otherwise.
  private func addMenuItems(near id: LibraryItem.ID?) -> [OutlineMenuItem] {
    [
      .action("New Folder", systemImage: "folder.badge.plus") {
        add(.folder("New Folder"), near: id)
      },
      .action("New Document", systemImage: "doc.badge.plus") {
        add(.document("New Document"), near: id)
      },
    ]
  }

  private func move(_ id: LibraryItem.ID, into folder: LibraryItem.ID?) {
    do {
      try library.move(id, into: folder)
    } catch {
      onError(error)
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

  private func expandAll() {
    expansion = Set(library.allFolders.map(\.item.id))
  }

  private func collapseAll() {
    expansion = []
  }

  private func newFolder() {
    add(.folder("New Folder"), near: selection)
  }

  private func newDocument() {
    add(.document("New Document"), near: selection)
  }

  private func deleteSelection() {
    guard let selection else { return }
    library.delete(selection)
    self.selection = nil
  }

  /// Adds the item into `id` if it is a folder and next to it otherwise, or at the root level for
  /// `nil`, then opens the folder and selects the new item so it is visible.
  private func add(_ item: LibraryItem, near id: LibraryItem.ID?) {
    let folder = id.flatMap { library.item($0)?.isFolder == true ? $0 : library.parent(of: $0) }
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
