#if os(iOS)
  import UIKit

  /// Outline-specific commands for navigating visible rows and their hierarchy.
  enum OutlineKeyboardAction {
    case previous, next, expand, collapse, activate, toggle
  }

  /// Non-generic responder for Objective-C key-command selectors.
  final class SnagCollectionView: UICollectionView {
    var canHandleKeyboardAction: ((OutlineKeyboardAction) -> Bool)?
    var onKeyboardAction: ((OutlineKeyboardAction) -> Void)?
    weak var keyboardFocusTarget: UIView?
    /// The host's SwiftUI direction, which may differ from the application's language.
    var outlineLayoutDirection: UIUserInterfaceLayoutDirection?

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
      guard !containsActiveTextInput,
        modifiers.intersection([.command, .control, .alternate, .shift]).isEmpty
      else { return false }
      let input: String
      switch keyCode {
      case .keyboardLeftArrow: input = UIKeyCommand.inputLeftArrow
      case .keyboardRightArrow: input = UIKeyCommand.inputRightArrow
      default: return false
      }
      let action = action(for: input)
      guard canHandleKeyboardAction?(action) == true else { return false }
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

    private lazy var outlineCommands: [UIKeyCommand] = [
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

    override var keyCommands: [UIKeyCommand]? {
      // Hosted rename fields keep their text input, including spaces and cursor movement.
      guard !containsActiveTextInput else { return super.keyCommands }
      let commands = outlineCommands
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
          return canHandleKeyboardAction?(self.action(for: input)) == true
        }
        return [OutlineKeyboardAction.previous, .next, .expand, .collapse, .activate, .toggle]
          .contains { canHandleKeyboardAction?($0) == true }
      }
      return super.canPerformAction(action, withSender: sender)
    }

    private var containsActiveTextInput: Bool {
      func containsInput(_ view: UIView) -> Bool {
        if view.isFirstResponder, view is any UITextInput { return true }
        return view.subviews.contains(where: containsInput)
      }
      return containsInput(self)
    }

    func action(for input: String) -> OutlineKeyboardAction {
      switch input {
      case UIKeyCommand.inputUpArrow: return .previous
      case UIKeyCommand.inputDownArrow: return .next
      case "\r": return .activate
      case " ": return .toggle
      default:
        let pointsForward =
          (input == UIKeyCommand.inputRightArrow)
          != ((outlineLayoutDirection ?? effectiveUserInterfaceLayoutDirection) == .rightToLeft)
        return pointsForward ? .expand : .collapse
      }
    }

    @objc private func performOutlineCommand(_ command: UIKeyCommand) {
      guard let input = command.input, !containsActiveTextInput else { return }
      let action = action(for: input)
      guard canHandleKeyboardAction?(action) == true else { return }
      onKeyboardAction?(action)
    }
  }
#endif
