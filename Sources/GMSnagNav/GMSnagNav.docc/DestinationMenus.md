# Move and Copy Destination Menus

Offer the same host-validated destinations inside and outside the sidebar.

## Share one set of callbacks

``OutlineActions`` is a main-actor value with live getters and the host's existing drop callbacks.
It stores neither a tree nor a native view. Create it at the common parent of sidebar and detail:

```swift
let actions = OutlineActions(
  data: { library.roots }, children: \.children,
  isPinned: { library.isPinned($0.id) },
  validate: library.dropResult(for:)
) { proposal, operation in
  do {
    try library.performDrop(proposal, operation: operation)
    return true
  } catch {
    show(error)
    return false
  }
}
```

The getter must read the actual current model, rather than return an array copied earlier.
Callbacks stay synchronous and in memory. Perform the entire multi-source proposal atomically;
the host owns mutations, rollback and error details.

Use the same callbacks and pins in the outline:

```swift
.outlinePinned(actions.isPinned)
.onOutlineDrop(actions)
.outlineContextMenuItems { ids in
  [
    .menu("Move to", children: actions.destinationItems(
      for: ids, operation: .move, expanded: { expansion },
      isAvailable: { !isSearching && renamingID == nil },
      locale: locale, onCompletion: handleResult
    ) { $0.name }),
    .menu("Copy to", children: actions.destinationItems(
      for: ids, operation: .copy, expanded: { expansion },
      isAvailable: { !isSearching && renamingID == nil },
      locale: locale, onCompletion: handleResult
    ) { $0.name }),
  ]
}
```

Pass the SwiftUI environment locale explicitly, for example from `@Environment(\.locale)`.
Root and built-in submenu labels then follow host overrides as well as system preferences.
The host supplies its own localized element names and may override `rootTitle`.

## Use the same items in a detail view

Compute the items directly in `body`, so observable data, title and pin reads are tracked:

```swift
let items = actions.destinationItems(
  for: [itemID], operation: .move, expanded: { expansion },
  isAvailable: { !isSearching && renamingID == nil }, locale: locale
) { $0.name }

Menu("Move to") {
  OutlineMenuItems(items)
}
```

``OutlineMenuItems`` uses the same descriptors as native context menus. No outline needs to be
mounted: this works in the detail of a collapsed iPhone split view too. Share a model's immutable
action value across windows only when they mean that same model and policy; supply each window's
expansion, availability and completion separately. When a model or window is replaced, make its
old menu actions unavailable through a live `isAvailable` getter. Hiding the sidebar alone must
not disable the detail menu. Avoid storing the action value in the model captured by its getters.

## Destination and source rules

The menu contains root and every container, including empty and collapsed folders. A submenu
has its own Move Here or Copy Here entry so its parent remains selectable. Invalid target actions
remain visible and disabled. Leaves are not destinations. A pinned or section container may
receive items if the host permits it.

Destinations are `.root` or `.onto(id)`: the host decides where to put items inside that container.
The current parent is not automatically disabled; the host can append, prepend or reject it.

All selected identifiers are retained, including descendants initially carried by selected roots.
They are normalized in current model order again when chosen: a selected child moved out of its
selected parent is still transferred. Every selected identifier must still exist; each current
effective source must be unpinned. A missing or pinned source,
or one captured root becoming a descendant of another, cancels the whole action. Mixed pinned
and movable sources are not partially transferred. This is intentionally stricter than dragging,
which filters out rows that cannot be dragged. A movable ancestor still carries its subtree,
including pinned descendants. Changing the selection does not replace captured source IDs.

## Revalidate the advertised operation

On execution, current data, expansion, availability and host validation are read again without
the pointer-drag cache. A disappeared destination never falls back to root. Redirects must stay
inside the named destination, although the host may select an insertion index there. Pin-span
adjustments are revalidated by the existing drop resolver. Moves cannot create a subtree cycle.

Copy-to actions set `isCopyRequested` on every platform, including iOS. They require `.copy` from
the validator; a `.move` answer disables/rejects the action. The default validator accepts moves,
so the host must explicitly support copying. Move-to actions likewise cannot silently copy.

``OutlineActionResult`` reports completion, missing/protected sources, missing targets,
unavailability, rejection or a performer returning false. Completion runs once per chosen action,
never for menu construction or dismissal. The package shows no alerts and changes no selection,
expansion or focus. Hosts may reveal the current selection after a successful move. Copy IDs and
selection of new copies remain host-owned because the performer returns only `Bool`.

## See Also

- <doc:DragAndDrop>
