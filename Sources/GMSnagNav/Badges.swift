import SwiftUI

/// A non-interactive accessory at the trailing edge of an outline row or section header.
///
/// Your app owns the value and its meaning. Use ``SnagOutline/outlineBadge(_:)`` to display it;
/// return `nil` for rows without an accessory. Symbol and dot labels should describe the status,
/// not the icon or its color, and should be localized by your app.
public enum OutlineBadge: Equatable, Sendable {
  /// A localized numeric capsule. Zero and negative counts are hidden.
  /// Supply a descriptive label such as "3 unread messages" when the number needs context.
  case count(Int, accessibilityLabel: String? = nil)
  /// A short text capsule, such as "New". Empty or whitespace-only text is hidden.
  case text(String)
  /// A status symbol with an accessible description, such as "Synchronization failed".
  case symbol(systemImage: String, accessibilityLabel: String, tint: Color = .secondary)
  /// A small colored status dot with an accessible description, such as "Unread".
  case dot(accessibilityLabel: String, tint: Color = .accentColor)
  /// A circular progress indicator. `nil` means an operation with no known progress.
  /// Finite values are clamped to 0...1; non-finite values are treated as indeterminate.
  case progress(Double?, accessibilityLabel: String)

  var isVisible: Bool {
    switch self {
    case .count(let count, _): count > 0
    case .text(let text): !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    default: true
    }
  }

  func accessibilityDescription(locale: Locale = .current) -> String {
    switch self {
    case .count(let count, let label): label ?? count.formatted(.number.locale(locale))
    case .text(let text): text
    case .symbol(_, let label, _), .dot(let label, _): label
    case .progress(_, let label):
      if let value = progressValue {
        "\(label), \(value.formatted(.percent.precision(.fractionLength(0)).locale(locale)))"
      } else {
        label
      }
    }
  }

  var progressValue: Double? {
    guard case .progress(let value, _) = self, let value, value.isFinite else { return nil }
    return min(1, max(0, value))
  }
}

extension SnagOutline {
  /// Adds a badge or status indicator to the trailing edge of a row, including section headers.
  ///
  /// ```swift
  /// .outlineBadge { item in
  ///   item.children.map { .count($0.count) }
  /// }
  /// ```
  ///
  /// The accessory follows layout direction and does not intercept row gestures or keyboard
  /// focus. Its description is exposed to accessibility; the host's row content is preserved.
  /// Values are reevaluated when SwiftUI updates the outline, including changes with the same
  /// identifiers and hierarchy. Read observable status data in the closure or in the host's body
  /// so SwiftUI can observe it; the outline does not poll or start background work.
  ///
  /// Apply this modifier directly to the `SnagOutline`, before any other view modifier.
  ///
  /// - Parameter badge: Returns the accessory for an element, or `nil` to omit it.
  public func outlineBadge(_ badge: @escaping (Element) -> OutlineBadge?) -> Self {
    var copy = self
    copy.behavior.badge = badge
    return copy
  }
}

extension OutlineBehavior {
  /// Evaluate the provider in the SwiftUI body, where reads of observable host status are tracked.
  func resolvingBadges(in tree: OutlineTree<Element>) -> Self {
    guard let badge else { return self }
    var values: [Element.ID: OutlineBadge] = [:]
    var pending = tree.roots
    while let id = pending.popLast() {
      if let element = tree.element(id), let value = badge(element), value.isVisible {
        values[id] = value
      }
      pending.append(contentsOf: tree.children(of: id))
    }
    var copy = self
    copy.badge = { values[$0.id] }
    return copy
  }
}

/// Keeps the host content at the same structural position as accessories appear or disappear.
struct OutlineBadgedContent<Content: View>: View {
  let badge: OutlineBadge?
  @ViewBuilder let content: () -> Content

  var body: some View {
    HStack(spacing: 8) {
      content()
      if let badge, badge.isVisible {
        Spacer(minLength: 4)
        OutlineBadgeView(badge: badge)
          .layoutPriority(1)
      }
    }
    .frame(maxWidth: badge?.isVisible == true ? .infinity : nil, alignment: .leading)
  }
}

/// Uses system foreground/background styles so capsules remain readable on selected rows.
struct OutlineBadgeView: View {
  let badge: OutlineBadge
  @Environment(\.dynamicTypeSize) private var dynamicTypeSize
  @Environment(\.locale) private var locale

  var body: some View {
    visual
      .allowsHitTesting(false)
      .accessibilityElement(children: .ignore)
      .accessibilityLabel(badge.accessibilityDescription(locale: locale))
      .help(badge.accessibilityDescription(locale: locale))
  }

  @ViewBuilder private var visual: some View {
    switch badge {
    case .count(let count, _):
      capsule(Text(count, format: .number.locale(locale)).monospacedDigit())
    case .text(let text):
      capsule(Text(text))
    case .symbol(let systemImage, _, let tint):
      Image(systemName: systemImage)
        .font(.callout)
        .foregroundStyle(tint)
    case .dot(_, let tint):
      Circle().fill(tint).frame(width: 8, height: 8)
    case .progress:
      if let value = badge.progressValue {
        // SwiftUI's circular ProgressView is indeterminate on macOS. Draw the fraction on both
        // platforms so a known progress value is visible rather than represented as a spinner.
        ZStack {
          Circle().stroke(.quaternary, lineWidth: 2)
          Circle().trim(from: 0, to: value)
            .stroke(.tint, style: StrokeStyle(lineWidth: 2, lineCap: .round))
            .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
      } else {
        ProgressView().controlSize(.small).frame(width: 16, height: 16)
      }
    }
  }

  private func capsule(_ text: some View) -> some View {
    text
      .font(.caption)
      .foregroundStyle(.primary)
      .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
      .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: true)
      .padding(.horizontal, 6)
      .padding(.vertical, 2)
      .background(.quaternary, in: Capsule())
  }
}
