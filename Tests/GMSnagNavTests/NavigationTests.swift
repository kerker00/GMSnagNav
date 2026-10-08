import SwiftUI
import Testing

@testable import GMSnagNav

@MainActor
@Suite struct NavigationTests {
  @Test func repeatedActionsHaveIndependentIdentities() {
    let first = OutlineNavigationRequest<String>.reveal("a")
    let second = OutlineNavigationRequest<String>.reveal("a")
    #expect(first.id != second.id)
    #expect(first.target == "a")
    #expect(!first.takesFocus)
    #expect(OutlineNavigationRequest<String>.focus().target == nil)
    #expect(OutlineNavigationRequest<String>.focus().takesFocus)
  }

  @Test func coalescesUpdatesAndClearsBeforeCompletion() async {
    var request: OutlineNavigationRequest<String>? = .reveal("a")
    var executions = 0
    var completions = 0
    let handler = OutlineNavigationHandler(
      request: Binding(get: { request }, set: { request = $0 }),
      onCompletion: { _, result in
        #expect(request == nil)
        #expect(result == .completed)
        completions += 1
      })
    let driver = OutlineNavigationDriver<String>()
    for _ in 0..<3 {
      driver.update(handler) { _ in
        executions += 1
        return .completed
      }
    }
    #expect(executions == 0)
    #expect(request != nil)
    await driver.settled()
    #expect(executions == 1)
    #expect(completions == 1)
  }

  @Test func replacingAQueuedRequestRunsOnlyTheLatest() async {
    var request: OutlineNavigationRequest<String>? = .reveal("a")
    var targets: [String?] = []
    var completions = 0
    let handler = OutlineNavigationHandler(
      request: Binding(get: { request }, set: { request = $0 }),
      onCompletion: { _, _ in completions += 1 })
    let driver = OutlineNavigationDriver<String>()
    let perform: @MainActor (OutlineNavigationRequest<String>) -> OutlineNavigationResult = {
      targets.append($0.target)
      return .completed
    }
    driver.update(handler, perform: perform)
    request = .reveal("b")
    driver.update(handler, perform: perform)
    await driver.settled()
    #expect(targets == ["b"])
    #expect(completions == 1)
  }

  @Test func clearingTheBindingCancelsEvenWithoutAnotherUpdate() async {
    var request: OutlineNavigationRequest<String>? = .focus()
    let handler = OutlineNavigationHandler(
      request: Binding(get: { request }, set: { request = $0 }),
      onCompletion: { _, _ in Issue.record("A cancelled request completed") })
    let driver = OutlineNavigationDriver<String>()
    driver.update(handler) { _ in
      Issue.record("A cancelled request executed")
      return .completed
    }
    request = nil
    await driver.settled()
  }

  @Test func completionCanQueueAnotherAction() async {
    var request: OutlineNavigationRequest<String>? = .reveal("a")
    var results: [OutlineNavigationResult] = []
    let handler = OutlineNavigationHandler(
      request: Binding(get: { request }, set: { request = $0 }),
      onCompletion: { _, result in
        results.append(result)
        if results.count == 1 { request = .focus() }
      })
    let driver = OutlineNavigationDriver<String>()
    driver.update(handler) { _ in .elementNotFound }
    await driver.settled()
    #expect(request?.takesFocus == true)
    driver.update(handler) { _ in .completed }
    await driver.settled()
    #expect(results == [.elementNotFound, .completed])
    #expect(request == nil)
  }

  @Test func storesNavigationAlongsideAutomaticRevealSetting() {
    let outline = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlineRevealsSelection(false)
      .outlineNavigation(.constant(.reveal("a2x")))
    #expect(outline.behavior.navigation?.request.wrappedValue?.target == "a2x")
    #expect(!outline.behavior.revealsSelection)
  }
}
