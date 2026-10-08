# Platform Differences

How the outline behaves on macOS compared with iOS and iPadOS.

## Overview

``SnagOutline`` has one API on every platform, but each platform renders it with its own native
control: an `NSOutlineView` on macOS and a `UICollectionView` list on iOS and iPadOS. Both follow
the conventions of their platform — Finder and Mail on the Mac, the Files app on iPhone and
iPad — so some interactions differ. Your bindings and callbacks receive the same values on both.

### Selection

| | macOS | iOS and iPadOS |
|---|---|---|
| Select | Click, or the arrow keys | Tap, or up/down with a hardware keyboard |
| Select several | Command-click and Shift-click | Tap each row; tapping a selected row deselects it |
| Row that can't be selected | A click on a container expands or collapses it | A tap on a container expands or collapses it |
| Select by typing | Typing the start of a row's text, with ``SnagOutline/outlineTypeSelect(_:)`` | Not available |
| Selection set by the app | Revealed: containers above it open, and the row scrolls into view | Revealed the same way |
| Explicit reveal or keyboard focus | `outlineNavigation(_:onCompletion:)`, preserving selection | Same API; the host controls split-view visibility |

Rows that ``SnagOutline/outlineSelectable(_:)`` excludes never become part of the selection, and
clicking or tapping them keeps the current selection; the arrow keys skip them. Collapsing a
container keeps its hidden elements selected on both platforms, and their rows appear selected
again once it opens. On macOS, when the outline also has a primary action, a single click on such a container toggles it
only after the double-click interval has passed, so a double-click can run the action instead.

### Primary action

``SnagOutline/outlinePrimaryAction(_:)`` runs on a double-click, Command-O or Command-Down on macOS.
Return also runs it when it does not start renaming. On iOS and iPadOS, a tap selects the row first
and runs the action; hardware-keyboard Return activates the focused row. The action receives the whole
selection when the row is part of it, and the row alone otherwise. Return applies to the current
selection.

### Hardware keyboards on iPad

Up and Down move UIKit's focus between visible rows. Selection follows focus on selectable rows;
section headers and other unselectable containers can receive focus without becoming selected or
opening as a side effect. Return or Space toggles a focused unselectable container.

The forward arrow expands a container, or enters its first child if already expanded. The backward
arrow collapses it, or returns to its parent. In a right-to-left interface, Left points forward
and Right backward; the disclosure chevrons mirror too. Space toggles a container, or runs the
primary action on a leaf. An active rename field keeps spaces, Return and cursor keys for editing.

### Reordering

With ``SnagOutline/outlineReorderable(_:)``, Command-Option-Up/Down moves one selected row on
macOS or one focused row on iPad by one sibling position. VoiceOver offers the same localized
actions on eligible rows on both platforms, independently of selection. Text fields keep their
shortcuts. Unavailable moves do nothing; they do not fall through to native arrow navigation.
Both renderers validate and perform through ``SnagOutline/onOutlineDrop(validate:perform:)``.

### Renaming

With ``SnagOutline/outlineRenaming(_:canRename:onRename:)``, a row turns into a text field while
it is renamed, on both platforms. Your app starts renaming by setting the binding, for example
from a context menu item. On macOS, Return also starts renaming when exactly one renamable row is
selected, as in the Finder; the primary action then runs on a double-click, and Return still runs
it for several selected rows. Escape cancels renaming on macOS; on iOS and iPadOS, the text field
commits when it loses focus.

On iPhone, a tap usually opens the detail of a collapsed `NavigationSplitView`. Use
``SwiftUICore/View/outlineCompactNavigation(selection:column:)`` for that instead of a primary
action.

### Swipe actions

``SnagOutline/outlineSwipeActions(edge:allowsFullSwipe:_:)`` shows actions when the user swipes a
row on iOS and iPadOS, at the leading or trailing edge, like in Mail. macOS shows no swipe
actions, so offer the same actions in a context menu there.

### Context menus

Both context menu modifiers receive the same identifiers: the selection when the pressed row is
part of it, and the pressed row alone otherwise.

- ``SnagOutline/outlineContextMenuItems(_:)`` builds a native menu on both platforms. On iOS and
  iPadOS, the menu and dragging share one long press, like in the Files app: moving the finger
  drags the row, holding it still opens the menu.
- ``SnagOutline/outlineContextMenu(_:)`` accepts any SwiftUI menu content. On iOS and iPadOS, its
  menu appears first when the user long-presses a row; the row can then be dragged out of the
  menu's preview.

In an outline with selection, a right-click on the empty space below the rows opens the menu with
an empty set of identifiers — useful for actions such as “New Folder”. On iOS and iPadOS, only
``SnagOutline/outlineContextMenuItems(_:)`` offers a menu on empty space; a SwiftUI menu there
would lift the whole outline as its preview.

### Drop targets

Both platforms propose the same kinds of ``OutlineDropTarget``: onto a row, and between rows at a
nesting level. They differ in how the pointer or finger picks one.

| | macOS | iOS and iPadOS |
|---|---|---|
| Onto a row | The pointer rests on the row | The finger rests on the middle half of the row |
| Between rows | The system's insertion indicator; the horizontal position picks the nesting level | The upper or lower quarter of a row; the gap belongs to the row above it |
| Empty space below the rows | Onto the root level (``OutlineDropTarget/root``) | At the end of the root level |
| Above the first row | At the start of the root level | At the start of the root level |
| Feedback | The system's drop highlight and insertion line | A highlight on the row or an insertion line drawn by the outline |
| Copy instead of move | Hold the Option key (``OutlineDropProposal/isCopyRequested``) | Not available |

On iOS and iPadOS, a gap between rows inserts after the row above it: items moved to the lower
edge of the last row in an expanded folder stay inside it. The empty space below the last row
moves them to the end of the root level instead, with an insertion line at the outermost level.

On both platforms, ``OutlineDropResult/redirect(to:operation:)`` moves the drop indicator to the
new target.

### Empty containers

A container with an empty children array, such as an empty folder, shows no disclosure
indicator on either platform because there is nothing to reveal. It is still a valid drop
target: the user drops onto its row to move items into it.

### Spring-loaded folders

While the user drags, resting on a collapsed container opens it, and it closes again when the
pointer or finger moves elsewhere. Spring-loaded containers never change your expansion binding;
expand a container in your drop handler to keep it open after the drop.

| | macOS | iOS and iPadOS |
|---|---|---|
| Delay | The system's spring-loading delay | 0.6 seconds |
| Turned off | When the system setting is off, or with `springLoadingBehavior(.disabled)` | With `springLoadingBehavior(.disabled)` |

On macOS, `springLoadingBehavior(.enabled)` opens containers even when the system setting is off.

### Drags from outside the outline

On both platforms, an outline accepts only drags that started in the same outline. Rows travel as
in-process references rather than as data, so your identifiers need not be `Codable`. Drags from
other outlines or other apps are not accepted, and rows dragged out of the outline carry no data
that other apps can read.

### Appearance

``SnagOutline/outlineStyle(_:)`` selects the source-list style of `NSOutlineView` or the sidebar
style of `UICollectionView`. On macOS, `outlineAppKitConfiguration(_:)` gives access to the
underlying `NSOutlineView` for settings the package does not cover.

### Section headers

| | macOS | iOS and iPadOS |
|---|---|---|
| Header | A group row in the source list's header style | A bold heading |
| Show and hide | Click the header, or its show and hide button while the pointer rests on it | Tap the header, or its chevron at the trailing edge |
| Entries | Not indented below the header | Not indented below the header |
