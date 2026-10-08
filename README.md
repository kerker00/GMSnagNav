<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/images/icon-dark.png">
    <img src="docs/images/icon-light.png" width="128" height="128" alt="GMSnagNav icon">
  </picture>
</p>

<h1 align="center">GMSnagNav</h1>

<p align="center">
  A nested, drag-and-drop capable outline for SwiftUI — native on macOS, iOS and iPadOS.
</p>

> **What does SnagNav mean?** It stands for *snag navigation*: reliable, hands-on navigation through nested content, with selection, expansion, and drag and drop built in.

<p align="center">
  <a href="https://github.com/kerker00/GMSnagNav/actions/workflows/ci.yml?query=event%3Apull_request"><img src="https://github.com/kerker00/GMSnagNav/actions/workflows/ci.yml/badge.svg?event=pull_request" alt="CI"></a>
  <a href="https://github.com/kerker00/GMSnagNav/actions/workflows/coverage-badge.yml"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fraw.githubusercontent.com%2Fkerker00%2FGMSnagNav%2Fbadges%2Fcoverage.json" alt="Coverage"></a>
  <a href="https://swiftpackageindex.com/kerker00/GMSnagNav"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkerker00%2FGMSnagNav%2Fbadge%3Ftype%3Dswift-versions" alt="Swift versions"></a>
  <a href="https://swiftpackageindex.com/kerker00/GMSnagNav"><img src="https://img.shields.io/endpoint?url=https%3A%2F%2Fswiftpackageindex.com%2Fapi%2Fpackages%2Fkerker00%2FGMSnagNav%2Fbadge%3Ftype%3Dplatforms" alt="Platforms"></a>
  <a href="LICENSE"><img src="https://img.shields.io/github/license/kerker00/GMSnagNav" alt="License"></a>
</p>

## Screenshots

The 0.4.0 demo with row badges, status controls and Show in Sidebar.

| Appearance | macOS | iPad |
|---|---|---|
| Light | ![GMSnagNav 0.4.0 on macOS in light appearance](docs/images/macos-light-0.4.0.png) | ![GMSnagNav 0.4.0 on iPad in light appearance](docs/images/ipad-light-0.4.0.png) |
| Dark | ![GMSnagNav 0.4.0 on macOS in dark appearance](docs/images/macos-dark-0.4.0.png) | ![GMSnagNav 0.4.0 on iPad in dark appearance](docs/images/ipad-dark-0.4.0.png) |

## Why

SwiftUI's `List` can show a tree *or* reorder a flat list, but not both reliably: moving items
between levels of a hierarchy is where it breaks down, especially on macOS. GMSnagNav gives you
one SwiftUI API for arbitrarily deep trees with selection, expansion and real drag and drop:

- **macOS:** backed by a native `NSOutlineView` — system drop indicators, keyboard navigation,
  source-list styling and VoiceOver behave like in Finder or Mail.
- **iOS / iPadOS:** backed by a native `UICollectionView` list — the system's drag-and-drop
  interactions, drop indicators between rows and spring-loaded folders, like in the Files app.

## Design principles

- **You own your data.** Pass your own `Identifiable` values and a children key path, like
  `OutlineGroup`. The package keeps no second source of truth.
- **You decide what a drop means.** GMSnagNav reports *what* was dropped and *where*
  (onto an item, between rows, or the root). Your code validates and performs the move — whether
  your model is Core Data, SwiftData, the file system or plain values.
- **No dependencies.** Pure Swift, SwiftUI and the platform UI frameworks.
- **Explicit options, no magic.** Multi-selection, context menus, primary actions and
  drag-and-drop are opt-in modifiers.

## Features

- Arbitrarily deep trees with single, multiple or no selection and an optional expansion binding
- Drag and drop onto items, between rows and into the root, with host-side validation and
  redirection
- Spring-loaded expansion while dragging
- Context menus, swipe actions, primary action (double-click / Return / tap) and non-selectable
  rows
- Section headers, like "Favorites" in the Finder's sidebar
- Renaming in place, started with Return on macOS as in the Finder
- Copying with the Option key while dragging on macOS
- Type select on macOS and empty-state content for empty outlines and searches
- Revealing what the app selects: collapsed containers open and the row scrolls into view
- Explicit reveal and keyboard-focus requests, including an already-selected element
- Incremental, animated updates when your data changes
- Navigation of collapsed split views, such as on iPhone, from the selection
- Demo app for macOS and iOS

## Requirements

- macOS 26 or iOS / iPadOS 26
- Swift 6.2 or later (Xcode 26 or later)

## Installation

Add the package with Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/kerker00/GMSnagNav.git", from: "0.4.1")
]
```

## Usage

Show your own values with a children key path — `nil` marks a leaf, an array (possibly empty) a
container. Selection and expansion are sets of your identifiers:

```swift
import GMSnagNav
import SwiftUI

struct Item: Identifiable {
  let id: UUID
  var name: String
  var children: [Item]?
}

struct Sidebar: View {
  var library: Library
  @State private var selection: Set<Item.ID> = []
  @State private var expansion: Set<Item.ID> = []

  var body: some View {
    SnagOutline(
      library.roots, children: \.children, selection: $selection, expansion: $expansion
    ) { item in
      Label(item.name, systemImage: item.children == nil ? "doc" : "folder")
    }
    .outlineContextMenuItems { ids in
      ids.isEmpty
        ? []
        : [.action("Delete", systemImage: "trash", role: .destructive) { library.delete(ids) }]
    }
    .outlineDraggable()
    .onOutlineDrop { proposal in
      proposal.isDroppingIntoOwnSubtree ? .reject : .accept(.move)
    } perform: { proposal, _ in
      library.move(
        proposal.draggedIDs, into: proposal.target.parent,
        at: proposal.insertionIndexAfterRemoval)
    }
  }
}
```

`Library` stands for your own model; its `move` returns whether the move succeeded.

GMSnagNav never changes your data. When the user drops, `perform` receives the dragged
identifiers — only top-level ones, in display order — and the target: a parent (`nil` for the
root level) and, for drops between rows, the insertion index. `insertionIndexAfterRemoval` is
that index adjusted for removing the dragged items first, or `nil` for a drop onto an item, where
you typically append. After your model changes, the outline animates the rows to their new
place.

Identifiers must be unique across the whole tree. The demo app's
[`Library`](Examples/SnagNavDemo/SnagNavDemo/Model/Library.swift) shows a complete model with
validation and moves.

## Demo app

[`Examples/SnagNavDemo`](Examples/SnagNavDemo) is a multiplatform app for macOS and iOS that shows
how to add GMSnagNav with Swift Package Manager and how to use each feature. It grows with the
package.

The screenshots above come from the demo app. `Scripts/readme-screenshots.sh` takes them again on
macOS and an iPad simulator, in light and dark appearance.

## Documentation

The [documentation](https://swiftpackageindex.com/kerker00/GMSnagNav/documentation/gmsnagnav) on the Swift Package Index covers the whole API; in Xcode, build it
with **Product > Build Documentation**. Start with these articles:

- [Drag and Drop](https://swiftpackageindex.com/kerker00/GMSnagNav/documentation/gmsnagnav/draganddrop) — reading proposals, validating, redirecting and performing
  drops.
- [Platform Differences](https://swiftpackageindex.com/kerker00/GMSnagNav/documentation/gmsnagnav/platformdifferences) — where macOS and iOS behave differently,
  following the conventions of each platform.
- [Designing a Sidebar](https://swiftpackageindex.com/kerker00/GMSnagNav/documentation/gmsnagnav/designingasidebar) — recommendations for the app around the
  outline, after Mario Guzmán's Mac design guidelines.

## Badges and status

Keep your row content and add a host-owned accessory:

```swift
SnagOutline(items, children: \.children, selection: $selection) { item in
  OutlineLabel(item.name, systemImage: item.systemImage)
}
.outlineBadge { item in item.children.map { .count($0.count) } }
```

`OutlineBadge` also supports short text, status symbols, dots and progress. Values follow layout
direction, support accessibility descriptions and update with observable host state. See
[Badges and status](Sources/GMSnagNav/GMSnagNav.docc/BadgesAndStatus.md).

## Reordering without dragging

Apply `.outlineReorderable()` alongside `.onOutlineDrop(validate:perform:)` to offer
Command-Option-Up/Down on macOS and iPad, plus VoiceOver actions on eligible rows. Each action
moves one element by one position among its siblings using the existing drop validator and
performer. Selection stays with the element. Disable reordering for filtered or sorted views
whose order differs from the model:

```swift
.outlineReorderable { _ in !isSearching }
```

See [Drag and drop](Sources/GMSnagNav/GMSnagNav.docc/DragAndDrop.md) for boundaries, redirects
and host-owned execution.

## Show an element in the sidebar

Keep a request in state and bind it to the outline:

```swift
@State private var navigation: OutlineNavigationRequest<Item.ID>?

// Apply directly to SnagOutline:
.outlineNavigation($navigation) { request, result in
  // Handle .elementNotFound, .outlineUnavailable or .focusUnavailable as needed.
}

// From a button or other host action:
navigation = .reveal(item.id, focus: true)
// Or transfer keyboard focus without expanding or scrolling:
navigation = .focus()
```

Reveal opens ancestors and scrolls without changing selection, even when automatic selection
reveal is disabled. Each new request runs once and clears its binding before completion.
The host controls search filters and split-view visibility. See
[Explicit navigation](Sources/GMSnagNav/GMSnagNav.docc/OutlineNavigation.md).

## Roadmap

Ideas for versions after `0.4.1`, all planned to be backward compatible:

- Reusable move/copy destination menus and navigation between hierarchy levels
- Pinned rows with consistent drag-and-drop rules
- Large-tree benchmarks, followed by update optimizations and lazy loading where measurements
  show a need; include mostly collapsed trees and large sibling lists
- Custom drag previews
- Drops from other apps, such as file URLs
- Loading children asynchronously

## Contributing

Bug reports, ideas and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for how to
build, test and format the code, and the [Code of Conduct](CODE_OF_CONDUCT.md).

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
