import SwiftUI

struct ItemDetailView: View {
  @Environment(Library.self) private var library
  let itemID: LibraryItem.ID
  let onError: (Error) -> Void
  let onShowInSidebar: () -> Void

  @State private var name = ""

  var body: some View {
    if let item = library.item(itemID) {
      form(for: item)
        .navigationTitle(item.name)
        #if os(macOS)
          .navigationSubtitle(subtitle(for: item))
        #endif
        .onAppear { name = item.name }
        // Renaming in the sidebar must show here too; Return would otherwise restore the old name.
        .onChange(of: item.name) { name = item.name }
    }
  }

  private func kind(of item: LibraryItem) -> String {
    switch item.kind {
    case .section: "Section"
    case .folder: "Folder"
    case .document: "Document"
    }
  }

  private var location: some View {
    Text(library.path(to: itemID).joined(separator: " › "))
      .accessibilityIdentifier("detail-location")
  }

  #if os(macOS)
    /// Mario Guzmán's Mac layout: right-aligned labels with colons next to left-aligned controls,
    /// centered in the window, 20 points from its edges and 14 points below the toolbar, with
    /// the actions as a group of their own.
    private func form(for item: LibraryItem) -> some View {
      Form {
        Section {
          nameField
            .frame(width: 260)
          statusPicker
            .frame(width: 260)
          // Text rows keep the 6 points between stacked controls.
          Group {
            LabeledContent("Kind:", value: kind(of: item))
            // One line as wide as the fields, so a long path doesn't shift the whole form.
            LabeledContent("Location:") {
              location
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 260, alignment: .leading)
                .help(library.path(to: itemID).joined(separator: " › "))
            }
            if let children = item.children {
              LabeledContent("Items:", value: "\(children.count)")
            }
          }
          .padding(.vertical, 2)
        }
        Section {
          LabeledContent("Organize:") {
            EqualWidthStack(spacing: 6) {
              showInSidebarButton
              ItemActions(itemID: itemID, onError: onError)
            }
          }
          // A separate group: 8 points on top of the 6 between stacked controls.
          .padding(.top, 8)
        }
      }
      .formStyle(.columns)
      .padding(EdgeInsets(top: 14, leading: 20, bottom: 20, trailing: 20))
      .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
  #else
    private func form(for item: LibraryItem) -> some View {
      Form {
        Section {
          // iOS forms show a text field's title only as a placeholder, so label it explicitly.
          LabeledContent("Name") {
            nameField.multilineTextAlignment(.trailing)
          }
          statusPicker
          LabeledContent("Kind", value: kind(of: item))
          LabeledContent("Location") { location }
          if let children = item.children {
            LabeledContent("Items", value: "\(children.count)")
          }
        }
        Section {
          showInSidebarButton
          ItemActions(itemID: itemID, onError: onError)
        }
      }
      .formStyle(.grouped)
    }
  #endif

  private var showInSidebarButton: some View {
    Button("Show in Sidebar", systemImage: "sidebar.left", action: onShowInSidebar)
      .accessibilityIdentifier("detail-show-in-sidebar")
  }

  private var statusPicker: some View {
    Picker(
      "Status",
      selection: Binding(
        get: { library.item(itemID)?.status ?? .none },
        set: { library.setStatus(itemID, to: $0) })
    ) {
      ForEach(LibraryItem.Status.allCases, id: \.self) { status in
        Text(status.rawValue).tag(status)
      }
    }
    .accessibilityIdentifier("detail-status")
  }

  /// Where the item lives, and for folders how many items they hold.
  private func subtitle(for item: LibraryItem) -> String {
    let folder = library.parent(of: itemID).flatMap(library.item)?.name ?? "Top Level"
    guard let children = item.children else { return folder }
    return "\(folder) · \(children.count == 1 ? "1 item" : "\(children.count) items")"
  }

  private var nameField: some View {
    #if os(macOS)
      let title = "Name:"
    #else
      let title = "Name"
    #endif
    return TextField(title, text: $name)
      .onSubmit { library.rename(itemID, to: name) }
      .accessibilityIdentifier("detail-name")
  }
}

#if os(macOS)
  /// Stacks controls vertically and gives each the width of the widest, so similar stacked
  /// controls share one width. Pull-down menus keep their natural width, so the widest one sets it.
  struct EqualWidthStack: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
      let width = widest(subviews)
      let heights = subviews.map {
        $0.sizeThatFits(ProposedViewSize(width: width, height: nil)).height
      }
      return CGSize(
        width: width, height: heights.reduce(0, +) + spacing * CGFloat(max(subviews.count - 1, 0)))
    }

    func placeSubviews(
      in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
      let width = widest(subviews)
      var y = bounds.minY
      for subview in subviews {
        let size = ProposedViewSize(width: width, height: nil)
        subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading, proposal: size)
        y += subview.sizeThatFits(size).height + spacing
      }
    }

    private func widest(_ subviews: Subviews) -> CGFloat {
      subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
    }
  }
#endif
