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
    #expect(behavior { $0.id != "c" }.startRenaming("c", in: tree) == .refused)
    #expect(host.renaming == nil)
    #expect(behavior().startRenaming("missing", in: tree) == .refused)
    #expect(behavior().startRenaming("c", in: tree) == .started)
    #expect(host.renaming == "c")
  }

  @Test func clearsARenameThatIsStillPendingForTheRendererToRestart() {
    // The text field never got the focus, so the binding still names the row: starting again
    // must not be a no-op that SwiftUI ignores. The renderer names the row again after the
    // update that shows it without the field.
    host.renaming = "c"
    #expect(behavior().startRenaming("c", in: tree) == .restarting)
    #expect(host.renaming == nil)
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

  @Test func endingAnOldSessionPreservesTheNewTargetAndItsFocus() throws {
    var returnedFocus = false
    let behavior = behavior()
    host.renaming = "a1"
    let old = try #require(
      behavior.renameSession(for: "a1", in: tree) { returnedFocus = true })
    host.renaming = "c"
    old.end("A1", "Edited A1", true)
    #expect(host.renaming == "c")
    #expect(!returnedFocus)
    // Losing the old editor still commits its draft.
    #expect(host.renamed.map(\.0) == ["a1"])
    #expect(host.renamed.map(\.1) == ["Edited A1"])
  }

  @Test func anOldSessionCannotEndARestartForTheSameElement() throws {
    var focusReturns = 0
    let behavior = behavior()
    host.renaming = "c"
    let old = try #require(
      behavior.renameSession(for: "c", in: tree) { focusReturns += 1 })
    #expect(behavior.startRenaming("c", in: tree) == .restarting)
    host.renaming = "c"
    let restarted = try #require(
      behavior.renameSession(for: "c", in: tree) { focusReturns += 1 })
    old.end("C", nil, true)
    #expect(host.renaming == "c")
    #expect(focusReturns == 0)
    restarted.end("C", nil, true)
    #expect(host.renaming == nil)
    #expect(focusReturns == 1)
  }

  @Test func refreshingTheSameSessionKeepsItsCompletionValid() throws {
    let behavior = behavior()
    host.renaming = "c"
    let old = try #require(behavior.renameSession(for: "c", in: tree))
    #expect(behavior.renameSession(for: "c", in: tree) != nil)
    old.end("C", "Sea", false)
    #expect(host.renaming == nil)
    #expect(host.renamed.map(\.1) == ["Sea"])
  }

  @Test func aRenameCallbackCanStartANewSessionWithoutBeingCleared() throws {
    host.renaming = "a1"
    let host = host
    var behavior = behavior()
    behavior.renaming = OutlineRenameHandler(
      renaming: Binding(get: { host.renaming }, set: { host.renaming = $0 }),
      canRename: { _ in true }, onRename: { _, _ in host.renaming = "c" })
    let old = try #require(behavior.renameSession(for: "a1", in: tree))
    old.end("A1", "Edited A1", false)
    #expect(host.renaming == "c")
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
