# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Swift package skeleton for macOS 26 and iOS 26.
- `SnagOutline`, a SwiftUI view for nested outlines of the host's own data, with single, multiple
  or no selection and an optional expansion binding. Children are read through a key path or a
  closure. Rendered with SwiftUI on all platforms for now.
- Drag-and-drop vocabulary: `OutlineDropTarget`, `OutlineDropOperation`, `OutlineDropResult` and
  `OutlineDropProposal`, including detection of drops into a dragged element's own subtree and
  insertion indices adjusted for the removal of dragged siblings.
- `SnagNavDemo`, a multiplatform demo app in `Examples/`.
