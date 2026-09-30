# SnagNav Demo

A multiplatform SwiftUI app (macOS and iOS/iPadOS) that shows how to integrate GMSnagNav and
how to use its features. It grows with the package: every new feature is demonstrated here.

## Running the demo

1. Open `Examples/SnagNavDemo/SnagNavDemo.xcodeproj` in Xcode 26 or later.
2. Select the **SnagNavDemo** scheme and a destination — **My Mac** or an iPhone/iPad simulator.
3. Build and run.

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
  .package(url: "https://github.com/kerker00/GMSnagNav.git", from: "0.1.0")
],
targets: [
  .target(name: "MyApp", dependencies: ["GMSnagNav"])
]
```

> GMSnagNav has not tagged a release yet. Until `0.1.0`, depend on a specific commit or branch.

Then `import GMSnagNav` wherever you build your sidebar.

## What the demo shows

| Area | File | Status |
| --- | --- | --- |
| Host-owned tree model | [`Model/LibraryItem.swift`](SnagNavDemo/Model/LibraryItem.swift) | ✅ |
| Host-owned mutations: move with insertion index, cycle protection, rename, delete | [`Model/Library.swift`](SnagNavDemo/Model/Library.swift) | ✅ |
| Menu-based "Move to" fallback for keyboard and accessibility users | [`Sidebar/ItemActions.swift`](SnagNavDemo/Sidebar/ItemActions.swift) | ✅ |
| Sidebar with selection and expansion | [`Sidebar/SidebarView.swift`](SnagNavDemo/Sidebar/SidebarView.swift) | Plain `List` for now — switches to `SnagOutline` with the public API |
| Drag and drop onto items, between rows and into the root | — | Planned |
| Spring-loaded folders while dragging | — | Planned |
| Context menus, primary action, non-selectable rows | — | Planned |

The key idea: the demo's `Library` store — not GMSnagNav — decides whether a move is allowed and
performs it. Replace it with your Core Data, SwiftData or file-system layer in a real app.
