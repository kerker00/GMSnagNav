# Contributing to GMSnagNav

Thanks for your interest in improving GMSnagNav! This guide explains how to propose changes.

## Before you start

- **Bugs:** open an issue with the bug report template. A minimal reproduction (a small tree and
  the steps to trigger the problem) helps the most.
- **Features and API changes:** open an issue first so we can agree on the design before you
  invest time. GMSnagNav deliberately keeps a small, domain-free API — the package provides
  interaction mechanics, while the host app owns its data and decides what a drop means.
- **Questions:** use GitHub Discussions if enabled, otherwise an issue.

## Development setup

Requirements: Xcode 26 or later (Swift 6.2+), macOS 26.

```sh
git clone https://github.com/kerker00/GMSnagNav.git
cd GMSnagNav
swift build
swift test
```

Check that the package also builds for iOS:

```sh
xcodebuild -scheme GMSnagNav -destination 'generic/platform=iOS Simulator' build
```

### UI tests

The demo app has UI tests that drive the real app, including genuine mouse drags on macOS:

```sh
cd Examples/SnagNavDemo
xcodebuild test -project SnagNavDemo.xcodeproj -scheme SnagNavDemo -destination 'platform=macOS'
xcodebuild test -project SnagNavDemo.xcodeproj -scheme SnagNavDemo \
  -destination 'platform=iOS Simulator,name=<an installed simulator, e.g. iPhone 18 Pro>'
```

On macOS, grant Xcode (or your terminal) accessibility access when asked, and leave the mouse
alone while the tests run.

## Making changes

1. Fork the repository and create a branch from `main`.
2. Keep each pull request focused on one change. Small, reviewable commits are preferred over one
   large commit.
3. Add or update tests. Platform-neutral logic lives in `Core/` and must be covered by unit tests
   that run with `swift test`.
4. Document every public symbol with a DocC comment.
5. Update `CHANGELOG.md` under **Unreleased** for user-visible changes.

## Commit messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat(macos): drop between rows with insertion marker
fix(core): keep expansion when an item moves to another parent
docs: explain drop validation
```

Common types: `feat`, `fix`, `perf`, `refactor`, `test`, `docs`, `ci`, `chore`. Optional scopes:
`core`, `macos`, `ios`, `example`.

## Code guidelines

- Swift 6 language mode with strict concurrency; UI types are `@MainActor`.
- No third-party dependencies and no private Apple APIs.
- Public API avoids `fatalError` paths; invalid input is handled or rejected gracefully.
- Match the style of the surrounding code.

## Translations

The package's own texts — so far only what VoiceOver reads for the rows' disclosure indicators on
iOS — live in the string catalog `Sources/GMSnagNav/Resources/Localizable.xcstrings`. To add a
language, open the catalog in Xcode, add the language and translate every entry, then add the
translations to `Tests/GMSnagNavTests/LocalizationTests.swift`. The texts follow the host app's
language, so they appear only in apps that are localized for that language too.

## Formatting

Code is formatted with `swift format`, which ships with the Swift toolchain. The configuration
lives in `.swift-format` (2-space indentation, 100-column lines, documented public API, no force
unwraps or force tries).

```sh
# Format in place
swift format --in-place --recursive Package.swift Sources Tests Examples

# Check without changing files (this is what CI runs)
swift format lint --strict --recursive Package.swift Sources Tests Examples
```

## Code of Conduct

This project follows the [Code of Conduct](CODE_OF_CONDUCT.md). By participating, you agree to
uphold it.

## License

By contributing, you agree that your contributions are licensed under the [MIT License](LICENSE).
