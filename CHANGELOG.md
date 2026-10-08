# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Fixed

- On macOS, dot, progress and symbol badges stay visible on a selected row. Their tint used to
  vanish on the accent-colored selection, such as a blue unread dot on a blue row; they now take
  the row's high-contrast foreground there.
- On macOS, the badge of a section header no longer moves when the pointer rests on the header.
  The header keeps room for AppKit's show/hide button at all times.
- On macOS, badges in plain outlines keep a distance from the outline's trailing edge.
- On macOS, badges and section headers scale with large and small sidebar rows, like the rows'
  text.
- Clicking a row that can't be selected, such as a section header or an unselectable folder,
  no longer clears the selection on macOS. The arrow keys still skip such rows.
- Collapsing a folder on macOS keeps its selected elements in the selection binding, as on iOS,
  instead of clearing the selection and closing the detail view. Their rows appear selected
  again when the folder opens.
- Clicking a section header on macOS collapses or expands it once. AppKit toggles group rows
  on its own, and the outline used to toggle them a second time, undoing the click.
- On macOS, `outlineContextMenuItems(_:)` now shows a native menu. It opens anywhere in a row,
  including its indentation and the space beside a short title, outlines the row it applies to
  like the Finder, and no longer ends with an empty separator. A right-click beside a row's
  title used to open the menu for empty space instead.
- On macOS, the SwiftUI menu of `outlineContextMenu(_:)` opens across the whole width of a row's
  content. A right-click in a row's indentation no longer opens the menu for empty space.
- On macOS, resting the pointer on a badge shows its description as a tooltip again. The badge
  ignored the pointer, so its `help` text never appeared.
- Demo: the detail view shows names changed in the sidebar, deleting the selected item or its
  folder ends the selection, clearing the search reveals the selection, folder counts match the
  search results, a long location no longer shifts the detail form, and Return dismisses alerts.

## [0.4.0] - 2026-10-08

Keyboard navigation and right-to-left layout improvements, host-owned row badges,
accessible sibling reordering and explicit reveal and keyboard-focus requests.

### Added

- `outlineNavigation(_:onCompletion:)` accepts repeatable reveal and keyboard-focus requests
  without changing selection. It reports missing or filtered elements, unavailable outlines
  and focus failures; the demo's "Show in Sidebar" clears search and reveals the current item.

- `outlineReorderable(_:)` enables Command-Option-Up/Down on macOS and iPad and localized
  VoiceOver actions to move one element among its siblings through the existing drop callbacks.
  Boundaries, protected rows, active renaming and rejected proposals leave the model unchanged.

- `outlineBadge(_:)` and `OutlineBadge` for counts, short text, status symbols, dots and progress
  at the trailing edge of rows and section headers on both platforms. Observable host-status
  changes update the display without changing selection or expansion.
- Command-O and Command-Down run the primary action on macOS without starting inline renaming.
- Hardware-keyboard navigation on iPad: up/down focus with selection following selectable
  rows, forward/backward arrows to expand, collapse and navigate the hierarchy, Return to activate
  and Space to toggle containers. Unselectable headers remain outside the selection.
- Regression tests for keyboard commands, section toggling, inline renaming and focus restoration,
  plus accessibility checks in the demo UI tests.

### Fixed

- iOS updates with unchanged hierarchy and expansion refresh visible content without applying
  another hierarchical snapshot, including badge-only changes.
- Clicking a macOS outline row takes keyboard focus from the detail view; refreshing hosted
  rows preserves it for arrow-key navigation and primary-action shortcuts. Inline editors and
  controls retain their focus.
- macOS primary-action shortcuts also work when hosted SwiftUI row content owns the focus;
  text editors and interactive controls retain their shortcuts.
- `outlineCompactNavigation` changes columns only in compact layouts, as documented. Selecting
  an item in a side-by-side layout leaves the preferred split-view column unchanged.
- iOS selection eligibility queries no longer toggle unselectable containers; a deliberate tap
  handles expansion instead, so moving keyboard focus cannot unexpectedly open or close folders.
- iOS disclosure chevrons and horizontal keyboard commands follow right-to-left layout.
- `OutlineLabel` exposes its title once to accessibility and hides its decorative icon.
- Hosted iOS rows receive the host's layout direction and Dynamic Type size. Built-in labels,
  renamable text and section titles wrap at accessibility text sizes.
- The rename-restart regression test waits for the binding change instead of a polling deadline,
  avoiding false failures when native rendering occupies the main actor in CI.

## [0.3.0] - 2026-10-04

The outline reveals what the app selects, and renaming and section headers work properly on iOS
and iPadOS.

### Added

- `outlineRevealsSelection(_:)`: when the app selects an element — after adding it, from a link,
  or restored at launch — the outline expands the collapsed containers above it, adding them to
  the expansion binding, and scrolls it into view. Selections the user makes are left alone.

### Changed

- Revealing the app's selection is on by default. Pass `false` to `outlineRevealsSelection(_:)`
  to keep the expansion exactly as the user left it.

### Fixed

- Renaming in place on iOS and iPadOS starts with the whole name selected, so typing replaces it.
  UIKit dropped the selection when the text field became first responder and put the cursor at
  the end.
- Section headers on iOS and iPadOS open their context menu when pressed anywhere in the row, not
  only on the title.
- Return starts renaming again after a rename got stuck — for example after moving rows on the Mac,
  when the text field had not received the focus. A row that goes away while being renamed now
  keeps the typed name and ends renaming, and the text field asks for the focus once more if its
  first request got lost.

## [0.2.0] - 2026-10-04

Sidebars that feel at home on macOS: sections, renaming in place, type select, copying by
dragging with the Option key, and empty states. Everything is opt-in; existing outlines behave as
before.

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

[Unreleased]: https://github.com/kerker00/GMSnagNav/compare/0.4.0...HEAD
[0.4.0]: https://github.com/kerker00/GMSnagNav/compare/0.3.0...0.4.0
[0.3.0]: https://github.com/kerker00/GMSnagNav/releases/tag/0.3.0
[0.2.0]: https://github.com/kerker00/GMSnagNav/releases/tag/0.2.0
[0.1.1]: https://github.com/kerker00/GMSnagNav/releases/tag/0.1.1
[0.1.0]: https://github.com/kerker00/GMSnagNav/releases/tag/0.1.0
