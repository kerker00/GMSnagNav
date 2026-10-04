# ``GMSnagNav``

A nested, drag-and-drop capable outline for SwiftUI, native on macOS, iOS and iPadOS.

## Overview

``SnagOutline`` shows arbitrarily deep trees of your own `Identifiable` values with selection,
expansion, context menus and drag and drop. On macOS it is backed by a native `NSOutlineView`, on
iOS and iPadOS by a native `UICollectionView` list, so drop indicators, keyboard handling and
styling match the platform.

Your app keeps ownership of its data. Pass the root elements and how to read an element's
children, and bind the selection and expansion to sets of your identifiers:

```swift
SnagOutline(
  library.roots, children: \.children, selection: $selection, expansion: $expansion
) { item in
  Label(item.name, systemImage: item.children == nil ? "doc" : "folder")
}
.outlineDraggable()
.onOutlineDrop { proposal, _ in
  library.move(
    proposal.draggedIDs, into: proposal.target.parent, at: proposal.insertionIndexAfterRemoval)
}
```

A `nil` children array marks a leaf; an empty array marks a container that is currently empty.
Identifiers must be unique across the whole tree.

GMSnagNav never changes your data. It reports what the user dragged and where it would land; your
code decides whether the drop is allowed and performs it in its own model — Core Data,
SwiftData, the file system or plain values. After your data changes, the outline animates the
rows to their new place.

## Topics

### Essentials

- ``SnagOutline``
- ``OutlineLabel``
- <doc:PlatformDifferences>
- <doc:DesigningASidebar>

### Selection and actions

- ``SnagOutline/outlineSelectable(_:)``
- ``SnagOutline/outlineRevealsSelection(_:)``
- ``SnagOutline/outlinePrimaryAction(_:)``
- ``SnagOutline/outlineTypeSelect(_:)``
- ``SnagOutline/outlineRenaming(_:canRename:onRename:)``
- ``OutlineRenamableText``
- ``SnagOutline/outlineSwipeActions(edge:allowsFullSwipe:_:)``
- ``SwiftUICore/View/outlineCompactNavigation(selection:column:)``

### Context menus

- ``SnagOutline/outlineContextMenuItems(_:)``
- ``SnagOutline/outlineContextMenu(_:)``
- ``OutlineMenuItem``

### Drag and drop

- <doc:DragAndDrop>
- ``SnagOutline/outlineDraggable(_:)``
- ``SnagOutline/onOutlineDrop(validate:perform:)``
- ``OutlineDropProposal``
- ``OutlineDropTarget``
- ``OutlineDropResult``
- ``OutlineDropOperation``

### Appearance

- ``SnagOutline/outlineStyle(_:)``
- ``SnagOutline/outlineIndentation(_:)``
- ``SnagOutline/outlineSections(_:)``
- ``SnagOutline/outlineEmptyContent(_:)``
- ``SnagOutlineStyle``

### Diagnostics

- ``SnagOutline/onOutlineDuplicateIDs(_:)``

### Package information

- ``GMSnagNav/GMSnagNav``
