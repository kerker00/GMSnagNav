# Designing a Sidebar

Build a sidebar around the outline that feels at home on the Mac, iPhone and iPad.

## Overview

``SnagOutline`` takes care of the outline itself: native rows, selection, expansion and drag and
drop. How well the sidebar works also depends on what your app puts around it. The
recommendations below follow Mario Guzmán's
[Mac design guidelines](https://marioaguzman.github.io/design/), which build on Apple's Human
Interface Guidelines. The demo app in the repository follows them and shows each one in use.

### Keep the hierarchy shallow

People find their way through two levels of nesting at a glance. When your data goes deeper,
consider whether part of it belongs in the content column, or in a second list, rather than in
the sidebar. GMSnagNav handles any depth, so this is a decision about your data, not a limit of
the outline.

### Make actions available in more than one place

- **Bottom bar:** On macOS, keep the toolbar above the sidebar for the sidebar toggle and put
  the sidebar's actions — adding, removing, options — into a bar below it, for example with
  `safeAreaBar(edge:alignment:spacing:content:)`. Items in the toolbar above a narrow sidebar
  move into an overflow menu when space runs short.
- **Context menu:** Offer the common actions in ``SnagOutline/outlineContextMenuItems(_:)`` as
  well, so they are at hand where the pointer or finger already is.
- **Menu bar:** Every action in a toolbar or bottom bar should also be a menu command, for
  example "New Folder" in the File menu. Include `SidebarCommands()` for "Show Sidebar" and
  "Hide Sidebar" in the View menu.

### Offer an alternative to dragging

Drag and drop is quick with a pointer or finger, but not everyone can drag. Add a "Move to"
submenu to the context menu, and to the menu bar or the detail view, that lists the possible
destinations. It works with the keyboard and with VoiceOver, and it can use the same validation
as your drop handler.

### Fit the sidebar's width and titles

- Let the sidebar resize between about 225 and 400 points, for example with
  `navigationSplitViewColumnWidth(min:ideal:max:)`.
- Use ``OutlineLabel`` for row titles, so a title that does not fit shows in full in a tooltip.
- Title the window after the current item or section, never after your app.

### Search without surprises

A search field in the sidebar helps when there are many items. Show the matches together with the
containers that lead to them, and turn dragging off while searching — see
<doc:DragAndDrop#Turn-off-dragging-while-searching>.

When nothing matches, or the sidebar has no items yet, say so with
``SnagOutline/outlineEmptyContent(_:)`` rather than leaving the sidebar blank — for example with
`ContentUnavailableView.search(text:)`. Keep the actions to add items in the bottom bar and the
context menu; the empty content shows information only.

## See Also

- <doc:PlatformDifferences>
- <doc:DragAndDrop>
