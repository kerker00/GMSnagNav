# Explicit navigation

Reveal an element or transfer keyboard focus without changing the selection.

## Overview

Automatic selection reveal opens ancestors when the host selects a new element. An explicit
request also works for an already-selected element, unselectable rows and outlines without
selection. It remains available with `outlineRevealsSelection(false)`.
Explicit requests take precedence over automatic selection reveal in the same update.

```swift
@State private var navigation: OutlineNavigationRequest<Item.ID>?

SnagOutline(items, children: \.children, selection: $selection, expansion: $expanded) {
  Text($0.name)
}
.outlineNavigation($navigation) { request, result in
  if result == .elementNotFound {
    // The element was deleted or is absent from the current filtered tree.
  }
}

// The host exposes the sidebar and clears its filter before submitting this request.
navigation = .reveal(item.id, focus: true)
```

## Requests and results

Create a new ``OutlineNavigationRequest`` for each action. `.reveal(id)` expands the ancestors
in the expansion binding and scrolls the row into view. Add `focus: true` to transfer keyboard
focus to the outline. `.focus()` transfers keyboard focus without expanding or scrolling.
Neither action writes the selection binding. Keyboard focus does not move VoiceOver focus.

Execution occurs after the view update against the latest tree. Only one outline should consume
a request binding. Replacing or clearing a queued request cancels it without a completion call.
A request remains in the host's binding while the consuming outline is unmounted. Once handled,
the binding is cleared before the completion callback, which may enqueue another action.

``OutlineNavigationResult/completed`` means that reveal and any requested focus transfer
succeeded. `elementNotFound` means that the target is absent from the current tree, including
filtered-out rows; selection and expansion stay unchanged. `outlineUnavailable` indicates an
unattached native view or an unavailable row. `focusUnavailable` means the row was revealed,
but focus could not transfer, for example while inline renaming is active. A focus-only request
can also produce this result. Active rename bindings and drafts are preserved.

## Host-owned navigation

The package sees only the tree passed to it. It does not clear search, load missing data or
change `NavigationSplitView` column visibility. For "Show in Sidebar", expose the sidebar and
clear the filter in the host, then submit the request with the complete tree. The demo forwards
the request after resetting its sidebar search state. Returning to the sidebar on a collapsed
iPhone split view retains the demo's existing selection-clearing navigation behavior.

After a drop or external model change, request the identifier in the updated tree. A removed
element reports `elementNotFound` instead of changing selection or waiting indefinitely for it
to return. To restore a selection at launch, automatic selection reveal usually suffices;
explicit requests are useful when the selected identifier has not changed.
