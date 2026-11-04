#if os(macOS)
  import AppKit
  import SwiftUI
  import Testing

  @testable import GMSnagNav

  @MainActor
  @Suite struct HostingCellIdentityTests {
    final class Host {
      var observations: [String] = []
    }

    struct StatefulRow: View {
      let id: String
      let label: String
      let host: Host
      @State private var draft: String

      init(id: String, label: String, draft: String, host: Host) {
        self.id = id
        self.label = label
        self.host = host
        _draft = State(initialValue: draft)
      }

      var body: some View {
        Text(draft)
          .onChange(of: label, initial: true) { host.observations.append("\(label):\(draft)") }
      }
    }

    private func show(_ row: StatefulRow, in cell: HostingCellView) {
      cell.show(AnyView(row), for: row.id)
    }

    private func settle(_ window: NSWindow) {
      window.contentView?.layoutSubtreeIfNeeded()
      RunLoop.main.run(until: Date().addingTimeInterval(0.05))
      window.contentView?.layoutSubtreeIfNeeded()
    }

    @Test(arguments: [false, true])
    func rowStateFollowsElementIdentity(sameElement: Bool) {
      let host = Host()
      let cell = HostingCellView()
      show(StatefulRow(id: "A", label: "first", draft: "A", host: host), in: cell)
      let window = NSWindow(
        contentRect: CGRect(x: 0, y: 0, width: 320, height: 100), styleMask: [],
        backing: .buffered, defer: false)
      window.isReleasedWhenClosed = false
      window.contentView = cell
      defer { window.close() }
      settle(window)
      show(
        StatefulRow(id: sameElement ? "A" : "B", label: "updated", draft: "B", host: host),
        in: cell)
      settle(window)
      #expect(host.observations == ["first:A", sameElement ? "updated:A" : "updated:B"])
    }
  }
#endif
