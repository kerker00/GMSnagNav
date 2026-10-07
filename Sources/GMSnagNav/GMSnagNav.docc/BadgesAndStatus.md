# Badges and status

Show host-owned counts, short text, status symbols and progress without changing the row content.

## Add an accessory

Apply ``SnagOutline/outlineBadge(_:)`` directly to the outline. Return `nil` to omit the accessory;
zero or negative counts and blank text are also hidden. Counts and accessible percentages use the
outline's environment locale, including an override applied with `.environment(\.locale, ...)`.

```swift
SnagOutline(items, children: \.children, selection: $selection) { item in
  OutlineLabel(item.name, systemImage: item.systemImage)
}
.outlineBadge { item in
  if item.needsAttention {
    return .symbol(
      systemImage: "exclamationmark.triangle.fill",
      accessibilityLabel: "Needs attention", tint: .orange)
  }
  return item.children.map { .count($0.count) }
}
```

## Choose a representation

``OutlineBadge`` supports:

- `count(_:accessibilityLabel:)`: a numeric capsule; describe the number's meaning when needed,
  for example `"3 unread messages"`.
- `text(_:)`: a short capsule such as `"New"`.
- `symbol(systemImage:accessibilityLabel:tint:)`: a status icon with an accessible description.
- `dot(accessibilityLabel:tint:)`: a small status dot with an accessible description.
- `progress(_:accessibilityLabel:)`: a circular fraction for a value from 0 to 1, or an
  indeterminate spinner for `nil`. Out-of-range values are clamped; non-finite values become
  indeterminate. The accessible description includes the percentage when known.

Localize text and status descriptions in your app. A dot needs another way for users to understand
its meaning; use a familiar convention or explain it in the detail view. Symbols and descriptions
should communicate meaning without relying only on color.

## Preserve behavior and updates

Accessories appear at the trailing edge, including on section headers, and follow right-to-left
layout. They do not handle clicks, taps, drags or keyboard focus. Your row content, selection,
expansion, menus and renaming remain under the same APIs.

The provider is evaluated in the outline's SwiftUI body, so observable status reads trigger an
update even when identifiers and hierarchy do not change. Values are refreshed in visible rows.
On iOS a status-only update does not apply another hierarchical snapshot. Changes to hierarchy
or expansion continue to apply the snapshot normally.

The host owns counts, status, asynchronous work and errors. GMSnagNav displays these values;
it does not start synchronization or calculate domain-specific totals. Custom controls or more
complex accessories can still be included in your `rowContent`.
