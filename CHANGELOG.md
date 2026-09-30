# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Swift package skeleton for macOS 26 and iOS 26.
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
- `outlineStyle(_:)` with `SnagOutlineStyle` (automatic, sidebar, plain) and
  `outlineIndentation(_:)`.
- `outlineAppKitConfiguration(_:)` on macOS to customize the underlying `NSOutlineView`.
- `outlineDraggable(_:)` and `onOutlineDrop(validate:perform:)` for moving elements by drag and
  drop onto elements, between rows and into the root, with in-process drags that need no
  `Codable` identifiers. On iOS, a gap between rows inserts after the row above it, so items
  moved to the bottom of an expanded folder stay in it.
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
- `SnagNavDemo`, a multiplatform demo app in `Examples/`.
