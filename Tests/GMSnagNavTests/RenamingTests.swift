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
