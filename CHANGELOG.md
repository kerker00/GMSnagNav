# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Swift package skeleton for macOS 26 and iOS 26.
- `SnagOutline`, a SwiftUI view for nested outlines of the host's own data, with single, multiple
  or no selection and an optional expansion binding. Children are read through a key path or a
  closure. On macOS it renders with a native `NSOutlineView` in source-list style; on iOS and
  iPadOS with a SwiftUI `List`. On macOS, data changes are applied as animated inserts, removals
  and moves that keep expansion and selection.
- `outlineSelectable(_:)` to make elements non-selectable; clicking such a container toggles it.
- `outlinePrimaryAction(_:)` for double-click or Return on macOS and tap on iOS.
- `outlineContextMenu(_:)` for the clicked element, the selection, or empty space.
- `outlineStyle(_:)` with `SnagOutlineStyle` (automatic, sidebar, plain) and
  `outlineIndentation(_:)`.
- `outlineAppKitConfiguration(_:)` on macOS to customize the underlying `NSOutlineView`.
- `outlineDraggable(_:)` and `onOutlineDrop(validate:perform:)` for moving elements by drag and
  drop, with in-process drags that need no `Codable` identifiers (macOS).
- Spring-loaded folders while dragging on macOS: collapsed elements open after the system's
  spring-loading delay and close again when the pointer leaves, without changing the expansion
  binding. Respects `springLoadingBehavior(_:)`.
- Drag-and-drop vocabulary: `OutlineDropTarget`, `OutlineDropOperation`, `OutlineDropResult` and
  `OutlineDropProposal`, including detection of drops into a dragged element's own subtree and
  insertion indices adjusted for the removal of dragged siblings.
- `SnagNavDemo`, a multiplatform demo app in `Examples/`.
