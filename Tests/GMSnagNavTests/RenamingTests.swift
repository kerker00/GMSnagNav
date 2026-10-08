import SwiftUI
import Testing

@testable import GMSnagNav

@MainActor
@Suite struct RenamingTests {
  let tree = OutlineTree(sampleRoots, children: \.children)

  final class Host {
    var renaming: String?
    var renamed: [(String, String)] = []
  }

  let host = Host()

  private func behavior(canRename: @escaping (TestItem) -> Bool = { _ in true })
    -> OutlineBehavior<TestItem>
  {
    let host = host
    var behavior = OutlineBehavior<TestItem>()
    behavior.renaming = OutlineRenameHandler(
      renaming: Binding(get: { host.renaming }, set: { host.renaming = $0 }),
      canRename: canRename,
      onRename: { host.renamed.append(($0, $1)) })
    return behavior
  }

  @Test func offersASessionOnlyToTheRowBeingRenamed() {
    host.renaming = "c"
    #expect(behavior().renameSession(for: "c", in: tree) != nil)
    #expect(behavior().renameSession(for: "a", in: tree) == nil)
    #expect(behavior { $0.id != "c" }.renameSession(for: "c", in: tree) == nil)
    #expect(OutlineBehavior<TestItem>().renameSession(for: "c", in: tree) == nil)
  }

  @Test func startsRenamingOnlyRenamableElements() {
    #expect(!behavior { $0.id != "c" }.startRenaming("c", in: tree))
    #expect(host.renaming == nil)
    #expect(!behavior().startRenaming("missing", in: tree))
    #expect(behavior().startRenaming("c", in: tree))
    #expect(host.renaming == "c")
  }

  // The time limit only guards against a restart that never happens. On CI simulators, other
  // tests have blocked the main actor for over a minute while the system keyboard started up.
  @Test(.timeLimit(.minutes(5))) func restartsARenameThatIsStillPending() async {
    // The text field never got the focus, so the binding still names the row: starting again
    // must not be a no-op that SwiftUI ignores.
    host.renaming = "c"
    let (restarts, continuation) = AsyncStream<String>.makeStream()
    defer { continuation.finish() }
    let host = host
    var restarting = behavior()
    restarting.renaming = OutlineRenameHandler(
      renaming: Binding(
        get: { host.renaming },
        set: {
          host.renaming = $0
          if let id = $0 { continuation.yield(id) }
        }),
      canRename: { _ in true }, onRename: { _, _ in })
    #expect(restarting.startRenaming("c", in: tree))
    #expect(host.renaming == nil)
    // Wait for the binding write itself. Native rendering in other tests can occupy the main
    // actor past a polling deadline even though the restart is queued and will complete.
    var iterator = restarts.makeAsyncIterator()
    #expect(await iterator.next() == "c")
    #expect(host.renaming == "c")
  }

  @Test func commitsOnlyChangedNamesAndEndsRenaming() throws {
    host.renaming = "c"
    let session = try #require(behavior().renameSession(for: "c", in: tree))
    session.end("C", "C", false)
    #expect(host.renamed.isEmpty)
    #expect(host.renaming == nil)

    host.renaming = "c"
    try #require(behavior().renameSession(for: "c", in: tree)).end("C", "Sea", false)
    #expect(host.renamed.map(\.0) == ["c"])
    #expect(host.renamed.map(\.1) == ["Sea"])
    #expect(host.renaming == nil)
  }

  @Test func cancelsWithoutRenaming() throws {
    host.renaming = "c"
    try #require(behavior().renameSession(for: "c", in: tree)).end("C", nil, true)
    #expect(host.renamed.isEmpty)
    #expect(host.renaming == nil)
  }

  @Test func returnsTheFocusOnlyWhenEndedWithTheKeyboard() throws {
    var returns = 0
    host.renaming = "c"
    try #require(behavior().renameSession(for: "c", in: tree) { returns += 1 })
      .end("C", "Sea", false)
    #expect(returns == 0)

    host.renaming = "c"
    try #require(behavior().renameSession(for: "c", in: tree) { returns += 1 })
      .end("C", nil, true)
    #expect(returns == 1)
  }
}
