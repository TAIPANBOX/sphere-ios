# Contributing to Sphere (iOS)

Thank you for your interest in contributing.

## Before you start

- Open an issue first for non-trivial changes — discuss the approach before
  writing code.
- Read [docs/ROADMAP.md](docs/ROADMAP.md) for the dependency-ordered plan, and
  the `CLAUDE.md` at the repo root for the fixed architectural decisions.

## Setup

```bash
git clone https://github.com/TAIPANBOX/sphere-ios
cd sphere-ios

# Core package — pure Swift, no Xcode needed
cd SphereCore
swift build
swift test

# App target — generates the (gitignored) Xcode project
brew install xcodegen
cd .. && xcodegen generate
```

## Development loop

```bash
cd SphereCore
swift build          # SphereCore + SphereUI
swift test           # must stay green — 509 tests

# after touching app-target files (new files, project.yml), regenerate:
xcodegen generate
xcodebuild -project Sphere.xcodeproj -scheme Sphere \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

CI runs `swift build` + `swift test` on `SphereCore` and an app build against the
iOS Simulator. Both must be green.

## Conventions

- **Conventional Commits:** `feat:`, `fix:`, `refactor:`, `test:`, `docs:`,
  `chore:`. End messages with the `Co-Authored-By` trailer when pairing.
- **One PR = one logical change.** Don't bundle refactors with features.
- **Tests are mandatory.** Every public `SphereCore` API gets a test
  (swift-testing, `@Test`). Put logic in pure enums/structs and test them
  exhaustively; keep `@MainActor` stores thin.
- **No singletons in `SphereCore`.** Inject stores and services explicitly.
- **No network calls in Engram write paths.**
- **Platform code stays behind protocols.** HealthKit, Contacts, EventKit,
  Foundation Models, and MLX live behind Sendable protocols in `SphereCore`,
  implemented in the app target — `SphereCore` imports none of them.
- **`SphereUI` compiles on macOS too.** Guard iOS-only APIs
  (`#if os(iOS)` / `#if canImport(UIKit)`).
- **All repo content is in English** (code, comments, commits, docs). The only
  non-English strings are the Ukrainian localization values and i18n fixtures.

## Architecture invariants

- iOS 17+, watchOS 10+, Swift 6 strict concurrency.
- One additive GRDB migration per schema change — never edit a shipped migration.
- The screen-anatomy rule: a sphere screen keeps a hero + up to three inline
  sections and links out to `CRUDListScreen` for secondary lists.
- Free AI first: nothing may *require* an API key.

## What we're not looking for (without prior discussion)

- Breaking changes to shipped GRDB migrations.
- New mandatory dependencies, or MLX/HealthKit imports inside `SphereCore`.
- Loading a local model in the widget or watch extensions (memory jetsam).
- Features that require a running server.
