import SwiftUI
import Testing

@testable import GMSnagNav

@Suite struct BadgeTests {
  @Test func hidesEmptyCountsAndText() {
    #expect(!OutlineBadge.count(0).isVisible)
    #expect(!OutlineBadge.count(-1).isVisible)
    #expect(!OutlineBadge.text(" \n ").isVisible)
    #expect(OutlineBadge.count(1).isVisible)
    #expect(OutlineBadge.text("New").isVisible)
  }

  @Test func describesTheMeaningInsteadOfTheStatusColorOrSymbol() {
    #expect(
      OutlineBadge.count(3, accessibilityLabel: "3 unread messages")
        .accessibilityDescription() == "3 unread messages")
    #expect(OutlineBadge.count(3).accessibilityDescription() == 3.formatted())
    #expect(OutlineBadge.text("New").accessibilityDescription() == "New")
    #expect(
      OutlineBadge.dot(accessibilityLabel: "Unread", tint: .blue)
        .accessibilityDescription() == "Unread")
    #expect(
      OutlineBadge.symbol(systemImage: "exclamationmark.triangle", accessibilityLabel: "Failed")
        .accessibilityDescription() == "Failed")
  }

  @Test func normalizesProgressAndExposesThePercentage() {
    #expect(OutlineBadge.progress(-0.2, accessibilityLabel: "Syncing").progressValue == 0)
    #expect(OutlineBadge.progress(1.2, accessibilityLabel: "Syncing").progressValue == 1)
    #expect(OutlineBadge.progress(.nan, accessibilityLabel: "Syncing").progressValue == nil)
    #expect(OutlineBadge.progress(.infinity, accessibilityLabel: "Syncing").progressValue == nil)
    #expect(
      OutlineBadge.progress(nil, accessibilityLabel: "Syncing").accessibilityDescription()
        == "Syncing")
    let percentage = 0.4.formatted(.percent.precision(.fractionLength(0)))
    #expect(
      OutlineBadge.progress(0.4, accessibilityLabel: "Syncing")
        .accessibilityDescription() == "Syncing, \(percentage)")
  }

  @Test func formatsAccessibleNumbersUsingTheHostsLocale() {
    let english = Locale(identifier: "en_US")
    let german = Locale(identifier: "de_DE")
    let count = OutlineBadge.count(1234)
    #expect(count.accessibilityDescription(locale: english) == "1,234")
    #expect(count.accessibilityDescription(locale: german) == "1.234")
    let progress = OutlineBadge.progress(0.4, accessibilityLabel: "Uploading")
    #expect(progress.accessibilityDescription(locale: english) == "Uploading, 40%")
    #expect(progress.accessibilityDescription(locale: german) == "Uploading, 40\u{00A0}%")
    #expect(
      OutlineBadge.count(1234, accessibilityLabel: "Unread messages")
        .accessibilityDescription(locale: german) == "Unread messages")
  }

  @Test @MainActor func resolvesEachElementOnceIncludingCollapsedChildrenAndSections() {
    var visited: Set<String> = []
    var status = "New"
    let outline = SnagOutline(sampleRoots, children: \.children) { Text($0.id) }
      .outlineBadge { item in
        #expect(visited.insert(item.id).inserted)
        return item.id == "c" ? .text(status) : .count(0)
      }
    let tree = OutlineTree(sampleRoots, children: \.children)
    let first = outline.behavior.resolvingBadges(in: tree)
    #expect(visited.count == tree.count)
    #expect(first.badge?(sampleRoots[0]) == nil)
    #expect(first.badge?(sampleRoots[2]) == .text("New"))
    status = "Synced"
    // A resolved renderer is a consistent value snapshot; the next SwiftUI body gets new values.
    #expect(first.badge?(sampleRoots[2]) == .text("New"))
    visited.removeAll()
    let second = outline.behavior.resolvingBadges(in: tree)
    #expect(second.badge?(sampleRoots[2]) == .text("Synced"))
  }

  @Test func distinguishesReorderingMovesAndLeafContainerChanges() {
    let original = OutlineTree(sampleRoots, children: \.children)
    #expect(original.hasSameStructure(as: OutlineTree(sampleRoots, children: \.children)))
    #expect(
      !original.hasSameStructure(as: OutlineTree(sampleRoots.reversed(), children: \.children)))
    var changed = sampleRoots
    changed[1].children = nil
    #expect(!original.hasSameStructure(as: OutlineTree(changed, children: \.children)))
    changed = sampleRoots
    changed[1].children = [changed[0].children!.removeFirst()]
    #expect(!original.hasSameStructure(as: OutlineTree(changed, children: \.children)))
  }
}
