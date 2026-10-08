# SnagNav Demo

A multiplatform SwiftUI app (macOS and iOS/iPadOS) that shows how to integrate GMSnagNav and
how to use its features. It grows with the package: every new feature is demonstrated here.

## Running the demo

1. Open `Examples/SnagNavDemo/SnagNavDemo.xcodeproj` in Xcode 26 or later.
2. Select the **SnagNavDemo** scheme and a destination — **My Mac** or an iPhone/iPad simulator.
3. Build and run.

To run the demo on your own iPhone, iPad or Mac with your development team, create
`Examples/SnagNavDemo/Config/Signing.local.xcconfig` containing `DEVELOPMENT_TEAM = <your team ID>`.
The file is ignored by Git, so your team ID stays on your machine.

The project references the package in this repository as a **local** Swift package
(`../..`), so changes to the package sources show up in the demo immediately.

## Adding GMSnagNav to your own app

### Xcode project

1. Choose **File › Add Package Dependencies…**
2. Enter `https://github.com/kerker00/GMSnagNav.git`.
3. Pick a version rule and add the **GMSnagNav** library to your app target.

### Swift package

```swift
// Package.swift
dependencies: [
  .package(url: "https://github.com/kerker00/GMSnagNav.git", from: "0.3.0")
],
targets: [
  .target(name: "MyApp", dependencies: ["GMSnagNav"])
]
```

Then `import GMSnagNav` wherever you build your sidebar.

## What the demo shows

| Area | File | Status |
| --- | --- | --- |
| Host-owned tree model | [`Model/LibraryItem.swift`](SnagNavDemo/Model/LibraryItem.swift) | ✅ |
| Host-owned mutations: move with insertion index, cycle protection, rename, delete | [`Model/Library.swift`](SnagNavDemo/Model/Library.swift) | ✅ |
| Menu-based "Move to" fallback for keyboard and accessibility users | [`Sidebar/ItemActions.swift`](SnagNavDemo/Sidebar/ItemActions.swift) | ✅ |
| `SnagOutline` with selection and expansion bindings, expand/collapse all, revealing new items | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ Native `NSOutlineView` on macOS, `UICollectionView` on iOS |
| "Show in Sidebar" from the detail: clear search, show the sidebar, reveal the current item and transfer keyboard focus | [`ContentView.swift`](SnagNavDemo/ContentView.swift) and `outlineNavigation(_:onCompletion:)` | ✅ On a collapsed iPhone split view, the existing return-to-sidebar behavior clears selection |
| Drag and drop onto items, between rows and into the root, validated by the host | [`Model/Library.swift`](SnagNavDemo/Model/Library.swift) | ✅ Cycles are rejected, drops onto documents are redirected next to them |
| Spring-loaded folders while dragging | built in | ✅ Both platforms; on macOS it follows the system setting |
| Non-selectable folders (toggle in the Outline menu); clicking them expands and collapses | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ |
| Primary action: double-click, Command-O or Command-Down toggles folders and "opens" documents (macOS); Return starts renaming | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ |
| Hardware-keyboard navigation: up/down, hierarchy arrows and Space; mirrored arrows in RTL layouts (iPad) | built in | ✅ |
| Reorder one row among its siblings using Command-Option-Up/Down or VoiceOver; disabled while searching | `outlineReorderable(_:)` and the shared drop callbacks | ✅ |
| Counts, text, status symbols, dots and progress; edit Status in the detail view or toggle Show Badges | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ |
| Style, indentation and the AppKit configuration escape hatch (Outline menu) | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ |
| Native context menu built from `OutlineMenuItem`s — submenu with disabled targets, destructive delete, add at the root level on empty space; on iOS it shares the long press with dragging | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ |
| Section headers that group the top level ("New Section") | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ |
| Renaming in place, from the context menu or with Return on macOS | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ |
| Type select | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ macOS |
| Copying by dragging with the Option key | [`Model/Library.swift`](SnagNavDemo/Model/Library.swift) | ✅ macOS |
| Swipe to delete | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ iOS |
| Confirmation before deleting folders with content | [`Sidebar/DeleteConfirmation.swift`](SnagNavDemo/Sidebar/DeleteConfirmation.swift) | ✅ |
| Search with dragging turned off, empty content for an empty library and for searches without matches | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | ✅ |
| Actions in the bottom bar, the context menu and the menu bar | [`Sidebar/DemoCommands.swift`](SnagNavDemo/Sidebar/DemoCommands.swift) | ✅ |
| Opening the detail of a collapsed split view from the selection | [`ContentView.swift`](SnagNavDemo/ContentView.swift) | ✅ iPhone |

UI tests in [`SnagNavDemoUITests`](SnagNavDemoUITests) drive the real app on both platforms:
selection, search, context menus and real drags into a folder and onto a document, which is
redirected next to it. On macOS they also cover a rejected cycle, a moved folder that stays
expanded and dragging while searching; on iOS, swiping to delete, dropping at the edge of a row
and navigating in a collapsed split view. They also cover keyboard navigation, sections, selection
reveal and renaming with focus restoration; iPad tests include RTL, accessibility audits and large
text sizes. See `CONTRIBUTING.md` for how to run them.

The section audit currently records an expected Dynamic Type issue without an associated element,
also reproduced with the unchanged `0.3.0` package. It remains open for manual inspection; other
audit findings still fail the test.

The key idea: the demo's `Library` store — not GMSnagNav — decides whether a move is allowed and
performs it. Replace it with your Core Data, SwiftData or file-system layer in a real app.
