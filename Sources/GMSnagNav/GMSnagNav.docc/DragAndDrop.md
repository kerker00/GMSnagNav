# Drag and Drop

Let users move elements within the outline while your app decides what each drop means.

## Overview

GMSnagNav supplies the interaction: it lets rows be dragged, finds the position under the pointer
or finger, shows the drop indicator and opens collapsed containers while the user hovers over
them. It never changes your data. Instead it describes each possible drop as an
``OutlineDropProposal``, asks your app whether the drop is allowed, and hands the final proposal
back when the user drops.

Two modifiers turn this on:

```swift
SnagOutline(library.roots, children: \.children, selection: $selection) { item in
  Label(item.name, systemImage: item.systemImage)
}
.outlineDraggable { item in !item.isLocked }
.onOutlineDrop(validate: library.dropResult(for:)) { proposal, _ in
  library.move(
    proposal.draggedIDs, into: proposal.target.parent, at: proposal.insertionIndexAfterRemoval)
}
```

- ``SnagOutline/outlineDraggable(_:)`` decides which elements can be dragged. When the user drags
  a multiple selection, only its draggable elements come along.
- ``SnagOutline/onOutlineDrop(validate:perform:)`` validates drops while the user drags and
  performs the one they release.

Drags stay within one outline: rows travel as in-process references, so identifiers need not be
`Codable`, and drags from other outlines or apps are not accepted.

### Read the proposal

An ``OutlineDropProposal`` tells you what is dragged and where it would land.

- term ``OutlineDropProposal/draggedIDs``: The dragged elements in display order, without
  duplicates and without descendants of other dragged elements. When the user drags a folder
  together with one of its children, only the folder is listed, because the child moves along
  with it. Move every identifier as a whole subtree.
- term ``OutlineDropProposal/target``: Where the elements would land. Its
  ``OutlineDropTarget/parent`` becomes their new parent, `nil` standing for the root level. Its
  ``OutlineDropTarget/placement`` is either ``OutlineDropTarget/Placement/onto``, a drop onto
  the parent itself, or ``OutlineDropTarget/Placement/insert(childIndex:)``, a drop at an exact
  position among its children.
- term ``OutlineDropProposal/insertionIndexAfterRemoval``: The insertion index adjusted for the
  dragged elements that currently sit before it among the same siblings, or `nil` for a drop
  onto an element. If your move removes the elements before inserting them, insert at this
  index rather than at ``OutlineDropTarget/childIndex``.
- term ``OutlineDropProposal/isDroppingIntoOwnSubtree``: Whether the target lies inside one of the
  dragged elements. Moving an element into itself would create a cycle, so reject such drops.
- term ``OutlineDropProposal/isTargetExpanded``: Whether the target's parent is expanded — for
  example to decide whether a drop onto a collapsed folder appends or prepends.

For example, the root level holds `a`, `b` and `c`. The user drags `a` below `c`: the target is
``OutlineDropTarget/insert(into:at:)`` with the root level and index 3, while
``OutlineDropProposal/insertionIndexAfterRemoval`` is 2, the position at the end once `a` has been
removed.

### Validate while the user drags

`validate` runs while the pointer or finger moves over the outline, once for every new position
the elements could land at, and returns an ``OutlineDropResult``:

- ``OutlineDropResult/reject`` refuses the drop. The outline shows no indicator, and releasing
  there does nothing.
- ``OutlineDropResult/accept(_:)`` allows the drop at the proposed target, as a
  ``OutlineDropOperation/move`` or a ``OutlineDropOperation/copy``.
- ``OutlineDropResult/redirect(to:operation:)`` allows the drop at a different target. The
  outline shows the indicator there, and `perform` receives the redirected target. A redirect to
  a target that does not exist in the outline is treated as a rejection.

Redirects keep drops meaningful where the proposed target is not. Here, documents cannot contain
other items, so a drop onto a document inserts the items right after it:

```swift
func dropResult(for proposal: OutlineDropProposal<Item.ID>) -> OutlineDropResult<Item.ID> {
  // Moving a folder into itself or one of its subfolders would create a cycle.
  if proposal.isDroppingIntoOwnSubtree { return .reject }

  guard let parent = proposal.target.parent, let target = item(parent) else {
    return .accept(.move)
  }
  if target.isFolder { return .accept(.move) }

  guard let location = location(of: parent) else { return .reject }
  return .redirect(to: .insert(into: location.parent, at: location.index + 1), operation: .move)
}
```

Keep `validate` fast and free of side effects. The outline reuses its answer for a position during
the drag, but asks again after your data or expansion changes, and a quick drag across many rows
still asks for each of them. Look up what you need in memory rather than querying a database or
the file system. Without a
`validate` closure, the outline rejects drops into a dragged element's own subtree and accepts
everything else as a move.

### Perform the drop

When the user releases, `perform` receives the final proposal — with a redirected target already
applied — and the accepted operation. Change your data and return whether the change succeeded;
the outline then animates the rows to their new place.

A drop into a collapsed folder moves the items out of sight. Expand the folder in the same
change to show where they went:

```swift
.onOutlineDrop(validate: library.dropResult(for:)) { proposal, _ in
  let moved = library.move(
    proposal.draggedIDs, into: proposal.target.parent, at: proposal.insertionIndexAfterRemoval)
  if moved, let folder = proposal.target.parent {
    expansion.insert(folder)
  }
  return moved
}
```

Folders that opened while the user hovered over them during the drag close again when the drag
ends, unless your expansion binding contains them by then.

Perform the whole drop as one change. ``OutlineDropProposal/draggedIDs`` can hold several
elements from different parents; hosts with persistent stores should move them in a single
transaction, so a failure leaves the data unchanged.

### Copy with the Option key

On macOS, users copy instead of move by holding the Option key while they drag, as in the Finder.
The proposal reports this as ``OutlineDropProposal/isCopyRequested``, and the outline validates
again whenever the key changes. Accept such drops with ``OutlineDropOperation/copy`` to show the
copy cursor, and copy in `perform` when it receives that operation:

```swift
.onOutlineDrop { proposal in
  if proposal.isDroppingIntoOwnSubtree { return .reject }
  return .accept(proposal.isCopyRequested ? .copy : .move)
} perform: { proposal, operation in
  switch operation {
  case .move:
    library.move(
      proposal.draggedIDs, into: proposal.target.parent,
      at: proposal.insertionIndexAfterRemoval)
  case .copy:
    library.copy(proposal.draggedIDs, into: proposal.target.parent, at: proposal.target.childIndex)
  }
}
```

A copy leaves the originals in place, so insert at ``OutlineDropTarget/childIndex``, not at
``OutlineDropProposal/insertionIndexAfterRemoval``. The default validation ignores the request and
moves. iOS and iPadOS have no gesture to ask for a copy within an app, so
``OutlineDropProposal/isCopyRequested`` is always `false` there.

### Turn off dragging while searching

A search usually shows only the matching elements and the containers that lead to them. Filter
through the children closure, so your data is not copied, and give the search an expansion of its
own, so the user's expansion is back when the search ends:

```swift
SnagOutline(
  library.roots.filter { matches?.contains($0.id) ?? true },
  children: { item in item.children?.filter { matches?.contains($0.id) ?? true } },
  selection: $selection,
  expansion: isSearching ? $searchExpansion : $expansion
) { item in
  OutlineLabel(item.name, systemImage: item.systemImage)
}
.outlineDraggable { _ in !isSearching }
```

Turn dragging off while the outline is filtered. A drop between two matches has no clear position
in your data, where hidden elements may lie between them, and an insertion index refers to the
visible siblings only. After the search, the user moves elements in the complete outline.

### Test your drop handling

The public ``OutlineDropProposal/init(draggedIDs:target:isTargetExpanded:isDroppingIntoOwnSubtree:insertionIndexAfterRemoval:isCopyRequested:)``
creates proposals for unit tests of your validation and move logic. It takes its values as they
are: unlike the proposals the outline creates, it does not normalize the dragged identifiers or
derive the other values from your data.

```swift
let proposal = OutlineDropProposal(
  draggedIDs: [folder.id], target: .onto(subfolder.id), isDroppingIntoOwnSubtree: true)
#expect(library.dropResult(for: proposal) == .reject)
```

## Move without dragging

Add ``SnagOutline/outlineReorderable(_:)`` to expose Command-Option-Up and
Command-Option-Down on macOS and iPad, and localized Move Up / Move Down VoiceOver actions.
These move one element by one position among its siblings, including an entire container subtree.
They use the same ``SnagOutline/onOutlineDrop(validate:perform:)`` callbacks as dragging; the
outline still never changes your data. Use `insertionIndexAfterRemoval` when performing the move.

```swift
.outlineReorderable { _ in !isSearching }
.onOutlineDrop(validate: library.dropResult(for:)) { proposal, operation in
  do {
    try library.performDrop(proposal, operation: operation)
    return true
  } catch {
    return false
  }
}
```

Supply a predicate for protected rows or to disable reordering while searching, filtering or
sorting independently of the model. The predicate is separate from `outlineDraggable` so apps
can offer accessible reordering without enabling drag gestures.

Keyboard commands apply to exactly one selected row on macOS or focused row on iPad. Multiple
selections are not reordered. VoiceOver actions apply to their own row without changing selection.
Text editors retain their shortcuts, and reordering is unavailable during inline renaming.

No action is offered at a sibling-list boundary or when the host rejects the proposal. Validation
runs again when an action executes; earlier eligibility checks are not permission to bypass new
host rules. Copy results and redirects that change the parent or the requested sibling position
are rejected: Move Up / Move Down always means one sibling step. Matching redirects are allowed.
The host's performer reports success or failure as with a drop.

## See Also

- <doc:PlatformDifferences>
