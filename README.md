# GMSnagNav

A nested, drag-and-drop capable outline for SwiftUI — native on macOS, idiomatic on iOS and iPadOS.

> **Status: pre-release.** The API is under active development and will change before `0.1.0`.
> It is not ready for production use yet.

## Why

SwiftUI's `List` can show a tree *or* reorder a flat list, but not both reliably: moving items
between levels of a hierarchy is where it breaks down, especially on macOS. GMSnagNav gives you
one SwiftUI API for arbitrarily deep trees with selection, expansion and real drag and drop:

- **macOS:** backed by a native `NSOutlineView` — system drop indicators, keyboard navigation,
  source-list styling and VoiceOver behave like in Finder or Mail.
- **iOS / iPadOS:** rendered with SwiftUI and the platform's own drag-and-drop interactions.

## Design principles

- **You own your data.** Pass your own `Identifiable` values and a children key path, like
  `OutlineGroup`. The package keeps no second source of truth.
- **You decide what a drop means.** GMSnagNav reports *what* was dropped and *where*
  (onto an item, between rows, or the root). Your code validates and performs the move — whether
  your model is Core Data, SwiftData, the file system or plain values.
- **No dependencies.** Pure Swift, SwiftUI and the platform UI frameworks.
- **Explicit options, no magic.** Multi-selection, context menus, primary actions and
  drag-and-drop are opt-in modifiers.

## Planned features for 0.1.0

- Arbitrarily deep trees with selection and expansion bindings
- Drag and drop onto items, between rows and into the root, with host-side validation
- Spring-loaded expansion while dragging
- Context menus, primary action (double-click / Return / tap) and non-selectable rows
- Incremental, animated updates when your data changes
- Demo app for macOS and iOS

## Requirements

- macOS 26 or iOS / iPadOS 26
- Swift 6.2 or later (Xcode 26 or later)

## Installation

Add the package with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/kerker00/GMSnagNav.git", from: "0.1.0")
]
```

> No release has been tagged yet. Until then, depend on a specific commit.

## Acknowledgements

GMSnagNav is written from scratch. These projects shaped its design with their ideas and lessons
learned — thank you to their authors:

- [Sameesunkaria/OutlineView](https://github.com/Sameesunkaria/OutlineView) — `OutlineGroup`-style
  API and drop redirection.
- [ChimeHQ/Outline](https://github.com/ChimeHQ/Outline) — expansion and selection as sets of IDs,
  hosting SwiftUI rows in `NSOutlineView`.
- [dnadoba/Tree](https://github.com/dnadoba/Tree) — tree diffing with move inference.
- [umputun/agterm](https://github.com/umputun/agterm) — a production `NSOutlineView` sidebar with
  spring-loaded drags and UI-tested drag and drop.
- [shufflingB/swiftui-macos-tree-list-demo](https://github.com/shufflingB/swiftui-macos-tree-list-demo)
  — a careful study of the limits of pure-SwiftUI tree lists.
- [revblaze/SimpleSidebar](https://github.com/revblaze/SimpleSidebar) — minimal native sidebar setup.

## License

GMSnagNav is available under the MIT license. See [LICENSE](LICENSE) for details.
