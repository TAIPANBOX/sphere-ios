# Sphere iOS — CLAUDE.md

Native SwiftUI rewrite of the Flutter app in `../sphere` (frozen, reference
only). Full phased plan: `../sphere/planning/IOS_REWRITE_PLAN.md` — read it
before any non-trivial task.

## Fixed decisions

- **iOS 17+**, watchOS 10+. Swift 6 language mode, strict concurrency.
- **No Android**: this repo is iOS-only; the Flutter repo is the reference.
- **SwiftUI + `@Observable` stores** (one per sphere), no architecture frameworks.
- **GRDB.swift** for all persistence (sphere domain data + Engram, one DB family).
- **LLM providers**: cloud is **OpenRouter only** (one key, every hosted model)
  via the OpenAI-compatible engine; no direct vendor APIs. Local models are
  deliberately small only (≤ ~2.6B params / ≤ 1.6 GB, see `ModelCatalog`).
- **Sync**: CloudKit (CKSyncEngine), no custom server. Wearables via HealthKit,
  no per-service OAuth.
- Engram v2 (on-device reflection via Foundation Models, hybrid BM25+embedding
  recall) is a post-launch phase — do not start it without discussion.
- **English-only**: product ships English-only (decision 2026-07-07); do not
  add localization or a language switcher without discussion.

## Conventions

- All repo content in English (code, comments, commits, docs).
- Comments only where the code cannot express a constraint; no narration.
- Every public API in SphereCore gets tests (swift-testing, `@Test`).
- Run `swift test` in `SphereCore/` after every change to the package.
- No singletons in SphereCore — inject stores/services explicitly.
- No network calls in Engram write paths.

## Layout

- `SphereCore/` — SPM package (models, Engram, LLM, services). Testable on
  macOS via `swift test`; no UIKit/SwiftUI imports allowed inside.
- App / Widget / Watch Xcode targets: to be added (plan Phase 2+).
