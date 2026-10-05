#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing

  @testable import GMSnagNav

  /// Renders the package's SwiftUI views in an offscreen window, so their bodies run as in an
  /// app: the outline with every modifier, its empty content, renaming, menus and navigation.
  @MainActor
  @Suite struct RenderingTests {
    final class Host {
      var selection: String?
      var expansion: Set<String> = ["a"]
      var renaming: String?
      var renamed: [String] = []
    }

    let host = Host()

    private var selection: Binding<String?> {
      Binding(get: { [host] in host.selection }, set: { [host] in host.selection = $0 })
    }

    private var expansion: Binding<Set<String>> {
      Binding(get: { [host] in host.expansion }, set: { [host] in host.expansion = $0 })
    }

    private var renaming: Binding<String?> {
      Binding(get: { [host] in host.renaming }, set: { [host] in host.renaming = $0 })
    }

    /// Lays out `view` in an offscreen window and lets SwiftUI run its updates.
    @discardableResult
    private func render<Content: View>(_ view: Content) -> NSWindow {
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 320, height: 480), styleMask: [.titled],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = NSHostingView(rootView: view)
      window.contentView?.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      window.contentView?.layoutSubtreeIfNeeded()
      return window
    }

    private func outline(_ roots: [TestItem]) -> SnagOutline<[TestItem], OutlineLabel> {
      SnagOutline(roots, children: \.children, selection: selection, expansion: expansion) {
        OutlineLabel($0.id, systemImage: "folder")
      }
    }

    @Test func rendersAnOutlineWithEveryModifier() {
      host.renaming = "a1"
      let window = render(
        SnagOutline(sampleRoots, children: \.children, selection: selection, expansion: expansion) {
          OutlineLabel($0.id, systemImage: "folder")
        }
        .outlineSelectable { _ in true }
        .outlinePrimaryAction { _ in }
        .outlineContextMenuItems { _ in
          [.action("Delete", systemImage: "trash", role: .destructive) {}, .divider]
        }
        .outlineSwipeActions { _ in [] }
        .outlineDraggable()
        .onOutlineDrop { _, _ in true }
        .outlineSections { $0.id == "b" ? "B" : nil }
        .outlineTypeSelect { $0.id }
        .outlineRenaming(renaming) { [host] _, name in host.renamed.append(name) }
        .outlineRevealsSelection(false)
        .outlineEmptyContent { Text("Nothing") }
        .outlineStyle(.sidebar)
        .outlineIndentation(16)
        .outlineAppKitConfiguration { $0.rowSizeStyle = .large }
        .onOutlineDuplicateIDs { _ in })
      let outlineView = window.contentView?.firstDescendant(of: NSOutlineView.self)
      #expect(outlineView?.numberOfRows == 5)
      #expect(outlineView?.rowSizeStyle == .large)
      window.close()
    }

    @Test func rendersTheEmptyContentForAnEmptyOutline() {
      let window = render(
        outline([]).outlineEmptyContent { Text("Nothing here") }
          .outlineContextMenu { _ in Button("New Folder") {} })
      #expect(window.contentView?.firstDescendant(of: NSOutlineView.self)?.numberOfRows == 0)
      window.close()
    }

    @Test func rendersAnOutlineWithoutSelectionOrExpansionBinding() {
      let window = render(
        SnagOutline(sampleRoots, children: { $0.children }) { Text($0.id) }
          .outlineContextMenu { _ in Button("Info") {} })
      #expect(window.contentView?.firstDescendant(of: NSOutlineView.self)?.numberOfRows == 3)
      window.close()
    }

    @Test func rendersRenamableTextInAndOutsideARenamingRow() {
      var ended: [String?] = []
      let session = OutlineRenameSession { _, name, _ in ended.append(name) }
      render(
        VStack {
          OutlineRenamableText("Plain")
          OutlineRenamableText("Edited").environment(\.outlineRenameSession, session)
          OutlineLabel("Label", systemImage: "folder")
            .environment(\.outlineRenameSession, session)
        }
      ).close()
      #expect(ended.allSatisfy { $0 == nil || $0 == "Edited" || $0 == "Label" })
    }

    @Test func rendersMenuItemsAsSwiftUIContent() {
      // Inline rather than inside a closed menu, whose content SwiftUI builds only when it opens.
      render(
        VStack {
          OutlineMenuItemsView(items: [
            .action("New", systemImage: "plus") {},
            .action("Delete", role: .destructive) {},
            .action("Disabled", isDisabled: true) {},
            .divider,
            .menu("Move to", systemImage: "folder", children: [.action("Top Level") {}]),
            .menu("More", children: []),
          ])
        }
      ).close()
    }

    @Test func rendersCompactNavigation() {
      var column = NavigationSplitViewColumn.sidebar
      render(
        NavigationSplitView {
          outline(sampleRoots)
        } detail: {
          Text("Detail")
        }
        .outlineCompactNavigation(
          selection: selection, column: Binding(get: { column }, set: { column = $0 }))
      ).close()
      #expect(column == .sidebar)
    }
  }

  extension NSView {
    /// The first view of the given type in this view's subtree, depth first.
    fileprivate func firstDescendant<View: NSView>(of type: View.Type) -> View? {
      for subview in subviews {
        if let match = subview as? View ?? subview.firstDescendant(of: type) { return match }
      }
      return nil
    }
  }
#endif
