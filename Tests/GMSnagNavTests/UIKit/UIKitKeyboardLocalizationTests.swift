#if os(iOS)
  import SwiftUI
  import Testing
  import UIKit

  @testable import GMSnagNav

  @MainActor
  @Suite struct UIKitKeyboardLocalizationTests {
    @Test func siblingShortcutTitlesFollowTheHostLocaleWithoutReplacingCommands() throws {
      let view = SnagCollectionView(frame: .zero, collectionViewLayout: UICollectionViewLayout())
      view.outlineLayoutDirection = .leftToRight
      view.handlesReorderShortcuts = true
      view.handlesHierarchyShortcuts = true
      var action: OutlineKeyboardAction?
      view.canHandleKeyboardAction = { _ in true }
      view.onKeyboardAction = { action = $0 }
      view.outlineLocale = Locale(identifier: "en")
      let originals = try siblingCommands(in: view)

      for language in ["en", "de", "en"] {
        view.outlineLocale = Locale(identifier: language)
        let commands = try siblingCommands(in: view)
        #expect(commands[0] === originals[0])
        #expect(commands[1] === originals[1])
        #expect(
          commands[0].discoverabilityTitle
            == (language == "de" ? "Nach oben verschieben" : "Move Up"))
        #expect(
          commands[1].discoverabilityTitle
            == (language == "de" ? "Nach unten verschieben" : "Move Down"))

        for (index, command) in commands.enumerated() {
          #expect(command.wantsPriorityOverSystemBehavior)
          #expect(!command.allowsAutomaticLocalization)
          #expect(!command.allowsAutomaticMirroring)
          let selector = try #require(command.action)
          #expect(view.canPerformAction(selector, withSender: command))
          view.perform(selector, with: command)
          #expect(action == (index == 0 ? .moveUp : .moveDown))
        }

        let deeper = try #require(
          view.keyCommands?.first {
            $0.input == UIKeyCommand.inputRightArrow && $0.modifierFlags == [.command, .alternate]
          })
        #expect(
          deeper.discoverabilityTitle
            == (language == "de" ? "Eine Ebene tiefer verschieben" : "Move One Level Deeper"))
      }
    }

    private func siblingCommands(in view: SnagCollectionView) throws -> [UIKeyCommand] {
      try [UIKeyCommand.inputUpArrow, UIKeyCommand.inputDownArrow].map { input in
        try #require(
          view.keyCommands?.first {
            $0.input == input && $0.modifierFlags == [.command, .alternate]
          })
      }
    }
  }
#endif
