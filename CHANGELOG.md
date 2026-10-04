# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- `OutlineDropProposal.isCopyRequested`, set on macOS while the user holds the Option key during a
  drag. Accept such drops with `.copy` to copy elements as in the Finder; the default validation
  still moves.
- `outlineEmptyContent(_:)` to show content such as a `ContentUnavailableView` while the outline
  has no elements. It lets clicks and drops through, so dropping onto the root level and the
  context menu for empty space keep working.
- `outlineTypeSelect(_:)` to select a row by typing the start of its text on macOS, as in the
  Finder. Rows that cannot be selected are skipped.
- `outlineSections(_:)` to show top-level elements as section headers, like "Favorites" in the
  Finder's sidebar: group rows on macOS and bold headings on iOS, never selected, collapsible
  through the expansion binding, and draggable when `outlineDraggable(_:)` allows it.
- `outlineRenaming(_:canRename:onRename:)` to rename elements in a text field within their row,
  started through a binding and, on macOS, with Return as in the Finder: while it is on, Return
  renames a single selected row instead of running the primary action, which stays on
  double-click. `OutlineLabel` and section headers turn into the text field by themselves;
  `OutlineRenamableText` does the same in custom rows.

## [0.1.1] - 2026-10-02

### Added

- A privacy manifest (`PrivacyInfo.xcprivacy`) declaring the package's `UserDefaults` access
  (reason `CA92.1`), so apps that embed GMSnagNav pass App Store privacy validation.

## [0.1.0] - 2026-10-01

The first release: a native, drag-and-drop capable outline for SwiftUI on macOS, iOS and iPadOS.
It requires macOS 26 or iOS 26 and Swift 6.2.

### Added

- `SnagOutline`, a SwiftUI view for nested outlines of the host's own data, with single, multiple
  or no selection and an optional expansion binding. Children are read through a key path or a
  closure. It renders natively on both platforms: with an `NSOutlineView` in source-list style on
  macOS, and with a `UICollectionView` list on iOS and iPadOS. Data changes are applied as
  animated inserts, removals and moves that keep expansion and selection.
- `OutlineLabel`, a `Label` for rows whose truncated title shows in full in a tooltip on macOS,
  like native sidebar rows.
- `outlineSelectable(_:)` to make elements non-selectable; clicking such a container toggles it.
- `outlinePrimaryAction(_:)` for double-click or Return on macOS and tap on iOS, where the tap
  selects the row first.
- `outlineContextMenu(_:)` for the pressed element, the selection, or — on macOS — empty space,
  with free SwiftUI content. On iOS its menu appears first; the row can be dragged out of it.
- `outlineContextMenuItems(_:)` with `OutlineMenuItem` (actions, submenus, dividers) for a native
  context menu on both platforms. On iOS it shares the long press with dragging, like the Files
  app: moving the finger drags the row, holding it still opens the menu.
- `outlineSwipeActions(edge:allowsFullSwipe:_:)` for actions that appear when swiping a row on
  iOS and iPadOS, such as deleting it.
- `outlineStyle(_:)` with `SnagOutlineStyle` (automatic, sidebar, plain) and
  `outlineIndentation(_:)`.
- `outlineAppKitConfiguration(_:)` on macOS to customize the underlying `NSOutlineView`.
- `outlineDraggable(_:)` and `onOutlineDrop(validate:perform:)` for moving elements by drag and
  drop onto elements, between rows and into the root, with in-process drags that need no
  `Codable` identifiers. On iOS, a gap between rows inserts after the row above it, so items
  moved to the bottom of an expanded folder stay in it, and the empty space below the rows
  appends to the root level.
- Spring-loaded folders while dragging: collapsed elements open after a short delay — on macOS
  the system's spring-loading delay — and close again when the pointer or finger leaves, without
  changing the expansion binding. Respects `springLoadingBehavior(_:)`.
- `outlineCompactNavigation(selection:column:)` to open the detail of a collapsed
  `NavigationSplitView` — such as on iPhone — from an outline's selection.
- Drag-and-drop vocabulary: `OutlineDropTarget`, `OutlineDropOperation`, `OutlineDropResult` and
  `OutlineDropProposal`, including detection of drops into a dragged element's own subtree and
  insertion indices adjusted for the removal of dragged siblings. Dragged identifiers are
  normalized to top-level elements, so a descendant dragged along with its ancestor is left out.
  The host's validation is asked once per position during a drag.
- `onOutlineDuplicateIDs(_:)` to learn about identifiers that occur more than once. Only their
  first occurrence is shown; repeats are logged, and without a handler they stop at an assertion
  in debug builds.
- English and German texts for what VoiceOver reads on iOS. They follow the host app's language.
- `SnagNavDemo`, a multiplatform demo app in `Examples/`.

[Unreleased]: https://github.com/kerker00/GMSnagNav/compare/0.1.1...HEAD
[0.1.1]: https://github.com/kerker00/GMSnagNav/releases/tag/0.1.1
[0.1.0]: https://github.com/kerker00/GMSnagNav/releases/tag/0.1.0
