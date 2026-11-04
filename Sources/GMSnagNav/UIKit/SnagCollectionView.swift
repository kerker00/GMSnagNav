#if os(iOS)
  import UIKit

  /// Outline-specific commands for navigating visible rows and their hierarchy.
  enum OutlineKeyboardAction {
    case previous, next, expand, collapse, activate, toggle, moveUp, moveDown, indent, outdent
  }

  /// Non-generic responder for Objective-C key-command selectors.
  final class SnagCollectionView: UICollectionView {
    var canHandleKeyboardAction: ((OutlineKeyboardAction) -> Bool)?
    var onKeyboardAction: ((OutlineKeyboardAction) -> Void)?
    weak var keyboardFocusTarget: UIView?
    /// The host's SwiftUI direction, which may differ from the application's language.
    var outlineLayoutDirection: UIUserInterfaceLayoutDirection?
    var handlesReorderShortcuts = false
    var handlesHierarchyShortcuts = false
    var outlineLocale = Locale.current

    override var canBecomeFirstResponder: Bool { true }
    private var handledDirectionalPresses: Set<UIPress> = []

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      var remaining = presses
      for press in presses {
        if let key = press.key,
          handleDirectionalKey(key.keyCode, modifiers: key.modifierFlags)
        {
          handledDirectionalPresses.insert(press)
          remaining.remove(press)
        }
      }
      if !remaining.isEmpty { super.pressesBegan(remaining, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      let remaining = presses.subtracting(handledDirectionalPresses)
      handledDirectionalPresses.subtract(presses)
      if !remaining.isEmpty { super.pressesEnded(remaining, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
      let remaining = presses.subtracting(handledDirectionalPresses)
      handledDirectionalPresses.subtract(presses)
      if !remaining.isEmpty { super.pressesCancelled(remaining, with: event) }
    }

    /// Physical arrows bypass UIKit's competing horizontal focus commands, including the
    /// first key after touching a row. Matching press endings must not trigger another action.
    func handleDirectionalKey(
      _ keyCode: UIKeyboardHIDUsage, modifiers: UIKeyModifierFlags = []
    ) -> Bool {
      guard !containsActiveTextInput else { return false }
      let relevantModifiers = modifiers.intersection([.command, .control, .alternate, .shift])
      if relevantModifiers == [.command, .alternate] {
        let action: OutlineKeyboardAction
        switch keyCode {
        case .keyboardUpArrow: action = .moveUp
        case .keyboardDownArrow: action = .moveDown
        case .keyboardLeftArrow, .keyboardRightArrow:
          guard handlesHierarchyShortcuts else { return false }
          let forward =
            (keyCode == .keyboardRightArrow)
            != ((outlineLayoutDirection ?? effectiveUserInterfaceLayoutDirection) == .rightToLeft)
          action = forward ? .indent : .outdent
        default: return false
        }
        // Consume an unavailable opted-in move so native navigation cannot change selection.
        guard canHandleKeyboardAction?(action) == true else {
          return action == .indent || action == .outdent
            ? handlesHierarchyShortcuts : handlesReorderShortcuts
        }
        onKeyboardAction?(action)
        return true
      }
      guard relevantModifiers.isEmpty else { return false }
      let input: String
      switch keyCode {
      case .keyboardLeftArrow: input = UIKeyCommand.inputLeftArrow
      case .keyboardRightArrow: input = UIKeyCommand.inputRightArrow
      default: return false
      }
      guard let action = action(for: input), canHandleKeyboardAction?(action) == true
      else { return false }
      onKeyboardAction?(action)
      return true
    }

    @discardableResult func takeKeyboardFocus() -> Bool {
      guard !containsActiveTextInput else { return false }
      return becomeFirstResponder()
    }

    override var preferredFocusEnvironments: [any UIFocusEnvironment] {
      if let keyboardFocusTarget { return [keyboardFocusTarget] }
      return super.preferredFocusEnvironments
    }

    private lazy var outlineCommands: [UIKeyCommand] =
      [
        UIKeyCommand.inputUpArrow, UIKeyCommand.inputDownArrow,
        "\r", " ",
      ]
      .map { input in
        let command = UIKeyCommand(
          input: input, modifierFlags: [], action: #selector(performOutlineCommand(_:)))
        command.wantsPriorityOverSystemBehavior = true
        // Map physical arrows ourselves, using the actual view's layout direction.
        command.allowsAutomaticMirroring = false
        command.allowsAutomaticLocalization = false
        return command
      }
      + [UIKeyCommand.inputUpArrow, UIKeyCommand.inputDownArrow].map { input in
        let command = UIKeyCommand(
          input: input, modifierFlags: [.command, .alternate],
          action: #selector(performOutlineCommand(_:)))
        command.wantsPriorityOverSystemBehavior = true
        command.allowsAutomaticMirroring = false
        command.allowsAutomaticLocalization = false
        return command
      }

    override var keyCommands: [UIKeyCommand]? {
      // Hosted rename fields keep their text input, including spaces and cursor movement.
      guard !containsActiveTextInput else { return super.keyCommands }
      // Keep the registered commands, but refresh their labels from the current host locale.
      for command in outlineCommands where command.modifierFlags == [.command, .alternate] {
        command.discoverabilityTitle = outlineLocalized(
          command.input == UIKeyCommand.inputUpArrow ? "Move Up" : "Move Down",
          locale: outlineLocale)
      }
      let hierarchyCommands: [UIKeyCommand] =
        handlesHierarchyShortcuts
        ? [UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow].map { input in
          let command = UIKeyCommand(
            input: input, modifierFlags: [.command, .alternate],
            action: #selector(performOutlineCommand(_:)))
          command.wantsPriorityOverSystemBehavior = true
          command.allowsAutomaticMirroring = false
          command.allowsAutomaticLocalization = false
          let direction: OutlineHierarchyDirection =
            action(for: input, modifiers: [.command, .alternate]) == .indent
            ? .indent : .outdent
          command.discoverabilityTitle = outlineLocalized(direction.titleKey, locale: outlineLocale)
          return command
        } : []
      let commands = outlineCommands + hierarchyCommands
      // Keep registration stable as selection and focus change; canPerformAction decides which
      // commands are currently enabled. UICollectionView also publishes arrow commands, so keep
      // one command per shortcut so native focus cannot win over hierarchy navigation.
      let inherited = (super.keyCommands ?? []).filter { candidate in
        if candidate.modifierFlags.isEmpty,
          candidate.input == UIKeyCommand.inputLeftArrow
            || candidate.input == UIKeyCommand.inputRightArrow
        {
          return false
        }
        return !commands.contains {
          $0.input == candidate.input && $0.modifierFlags == candidate.modifierFlags
        }
      }
      return commands + inherited
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
      if action == #selector(performOutlineCommand(_:)) {
        guard !containsActiveTextInput else { return false }
        if let command = sender as? UIKeyCommand, let input = command.input {
          guard let outlineAction = self.action(for: input, modifiers: command.modifierFlags)
          else { return false }
          return canHandleKeyboardAction?(outlineAction) == true
        }
        return [
          OutlineKeyboardAction.previous, .next, .expand, .collapse, .activate, .toggle, .moveUp,
          .moveDown, .indent, .outdent,
        ]
        .contains { canHandleKeyboardAction?($0) == true }
      }
      return super.canPerformAction(action, withSender: sender)
    }

    private var containsActiveTextInput: Bool {
      func containsInput(_ view: UIView) -> Bool {
        if view.isFirstResponder, view is any UITextInput || view is UIControl { return true }
        return view.subviews.contains(where: containsInput)
      }
      return containsInput(self)
    }

    func action(for input: String, modifiers: UIKeyModifierFlags = []) -> OutlineKeyboardAction? {
      if modifiers == [.command, .alternate] {
        switch input {
        case UIKeyCommand.inputUpArrow: return .moveUp
        case UIKeyCommand.inputDownArrow: return .moveDown
        case UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow:
          let forward =
            (input == UIKeyCommand.inputRightArrow)
            != ((outlineLayoutDirection ?? effectiveUserInterfaceLayoutDirection) == .rightToLeft)
          return forward ? .indent : .outdent
        default: return nil
        }
      }
      guard modifiers.isEmpty else { return nil }
      switch input {
      case UIKeyCommand.inputUpArrow: return .previous
      case UIKeyCommand.inputDownArrow: return .next
      case "\r": return .activate
      case " ": return .toggle
      case UIKeyCommand.inputLeftArrow, UIKeyCommand.inputRightArrow:
        let pointsForward =
          (input == UIKeyCommand.inputRightArrow)
          != ((outlineLayoutDirection ?? effectiveUserInterfaceLayoutDirection) == .rightToLeft)
        return pointsForward ? .expand : .collapse
      default: return nil
      }
    }

    @objc private func performOutlineCommand(_ command: UIKeyCommand) {
      guard let input = command.input, !containsActiveTextInput else { return }
      guard let action = action(for: input, modifiers: command.modifierFlags),
        canHandleKeyboardAction?(action) == true
      else { return }
      onKeyboardAction?(action)
    }
  }
#endif
