# Moving Between Hierarchy Levels

Move a row into its previous sibling container or directly after its parent without dragging.

## Opt in independently

```swift
.outlineHierarchyMovable { _ in !isSearching }
.onOutlineDrop(actions)
```

``SnagOutline/outlineHierarchyMovable(keyboardShortcuts:_:)`` is independent of dragging and
sibling reordering. `outlineReorderable` keeps its existing Command-Option-Up/Down behavior.
Use `keyboardShortcuts: false` to offer hierarchy accessibility actions while retaining your
app's own keyboard bindings.

In left-to-right layouts, Command-Option-Right moves one level deeper and Command-Option-Left
moves one level up; right-to-left layouts mirror these horizontal commands. This package-chosen
binding is active only after opting in. Normal arrows, Tab, Return, Command-O and editor input
keep their existing roles. An unavailable opted-in command is consumed so native fallback
navigation cannot change selection instead.

## Predictable structural steps

Moving deeper uses only the immediately preceding sibling, if it is a container. The moved row
is inserted after that container's last direct child. Empty and collapsed containers are valid.
A preceding leaf does not trigger a search for some other folder.

Moving up inserts directly after the current parent among that parent's siblings. Other children
stay in their parent. A root row cannot move up. Moving a container carries its complete subtree
and preserves its expanded descendants.

Section headers are not moved and are not automatic indent destinations. Direct section children
cannot move out to root with this command. Ordinary levels inside a section work normally;
use explicit destination menus for deliberate moves between sections.

Pinned sources cannot move. A pinned container can still receive ordinary children. If pin-span
normalization or a host redirect would move the row somewhere other than the exact requested
position, the hierarchy action is unavailable. Copy answers and redirects to other containers
are rejected. Equivalent exact-position redirects are accepted.

## Current validation and selection

The keyboard acts on one visible selected row on macOS, or the selected/focused row on iPad.
Multiple selection blocks these commands, including other selected IDs currently hidden from
view. VoiceOver actions apply to their own row independently of the current selection; a normal
unselectable container may have actions when the host allows it. Renaming blocks movement.

Displayed availability uses the renderer's existing tree, with current eligibility and pin
predicates. It does not rebuild the host tree for every visible row. Availability is checked
again when an action executes. The original live eligibility and pin predicates are retained
even as SwiftUI observes them to update accessibility actions.
With ``OutlineActions`` installed, commands build a fresh tree from the host getter before
execution. The original closure-only drop API can use only the latest renderer snapshot, so the
host validator and performer must still enforce the current model's rules. Use matching children
and ordering for the action source and outline. Disable hierarchy movement for filtered/sorted
views whose sibling positions do not correspond to the host's mutation indices.

## Keep the moved row visible

Selection IDs are not rewritten. After the host reports success, the renderer waits for its
updated tree, verifies the new parent and then opens ancestors and scrolls to the moved row.
This is a separate one-time reveal because automatic selection reveal does not react to an
unchanged selection ID. Expansion of the moved subtree is retained.

New selection, explicit host navigation, a different structural move or detachment cancels an
outdated reveal. A newly active text editor is never overridden to reclaim keyboard focus.
Rejected and failed actions do not change package-owned expansion, scrolling or focus. The host
must perform mutations atomically; the package cannot undo a partial host operation.

## See Also

- <doc:DestinationMenus>
- <doc:OutlineNavigation>
