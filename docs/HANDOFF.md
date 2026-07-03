# Handoff — continuing the Sphere iOS rewrite

Written at the end of the Phase-1 core sprint (2026-07-03). The core was
built and reviewed with extra care; from here on the work is mostly
pattern-repetition. Read this once before touching the code.

Master plan: `../../sphere/planning/IOS_REWRITE_PLAN.md` (phases, decisions).
Repo rules: `../CLAUDE.md`. Flutter reference app: `../../sphere` (frozen).

## What exists and is trusted

| Piece | Where | Notes |
|---|---|---|
| Engram v1.5 | `SphereCore/Sources/SphereCore/Engram/` | Episodic memory, FTS5+BM25, access reinforcement, Ebbinghaus decay + prune. Schema import-compatible with the Dart `sphere.engram.db`. |
| LLM engines | `.../LLM/` | `AnthropicEngine` + `OpenAICompatibleEngine` (OpenAI, Gemini, OpenRouter) behind `LLMEngine`. Byte-level SSE parser. `LLMProviderID` maps 4 providers → 2 engines. |
| Agent layer | `.../Agent/` | `AgentService` (chat tool-loop, brief, insight + offline cache), `SphereToolRegistry`, `SpherePrompts`, `APIKeyStore` protocol. |
| Golden template | `.../Spheres/GoalsStore.swift`, `SphereUI/Goals/GoalsScreen.swift` | THE pattern to copy for the other 11 spheres. |
| Tests | `SphereCore/Tests/` | 83 tests, all green. `cd SphereCore && swift test`. |

Everything above is covered by tests — do not restructure it while porting
spheres. If something seems missing, check the Flutter source first; the
Dart file usually answers "what should this do".

## How to add a sphere (the recipe)

Copy the Goals pattern end to end. For sphere X:

1. **Model(s)** — port from `sphere/lib/shared/models/*.dart` into
   `SphereCore/Sources/SphereCore/Models/`. Struct, `Codable`, `Equatable`,
   `Identifiable`, `Sendable`; enums as `String` raw values (same names as
   Dart, they are persisted). Conform to `FetchableRecord, PersistableRecord`
   and set `databaseTableName`. Arrays/nested values become JSON columns
   automatically via Codable.
2. **Migration** — append `migrator.registerMigration("x-v1") { ... }` in
   `AppDatabase.swift` AFTER the existing ones. Never edit a shipped
   migration; add a new one.
3. **Store** — `SphereCore/Sources/SphereCore/Spheres/XStore.swift`:
   `@MainActor @Observable final class`, `init(database:engram:)`,
   `load() async throws`, async mutations that write to GRDB then update the
   published arrays. Call `engram?.note(agentId: SphereType.x.rawValue, ...)`
   on significant mutations only (new entries, completions — not every edit);
   copy the exact note wording from the Dart provider.
4. **Agent tools** — a `nonisolated var tools: [SphereTool]` on the store.
   Port definitions (name, description, JSON schema) verbatim from
   `sphere/lib/shared/services/sphere_tools.dart` — the model was prompted
   against those descriptions. Write tools get a `confirmation` closure;
   read-only lookups get `silent: true`. Handlers use `[weak self]`, validate
   input, throw `AgentToolInputError` for bad input.
5. **Screen** — `SphereUI/Sources/.../X/XScreen.swift` following
   `GoalsScreen`: store injected via init, `.task { try? await store.load() }`,
   sections as `sphereCard()` cards, mutations via `Task { try? await ... }`,
   add-flows as sheets, accent = `SphereTheme.accent(for: .x)`. Port the
   layout from the Flutter screen (`sphere/lib/features/x/screens/`).
6. **Tests** — mirror `GoalsStoreTests`: persistence round-trip through a
   second store on the same `AppDatabase`, derived-state math, tool execution
   through a real `SphereToolRegistry` (result JSON + confirmation label +
   sphere scoping), Engram note content.

Definition of done per sphere: `swift test` green, tool round-trip test
passes, screen compiles in `swift build`.

## Pitfalls we already hit (do not rediscover them)

- **`engram.note()` is fire-and-forget.** In tests, poll for the count
  instead of asserting immediately (see `addNotesIntoEngram`).
- **Swift 6 strict concurrency is on.** No `Any` JSON — use `JSONValue`.
  Shared mutable test doubles are `final class ... @unchecked Sendable` with
  an `NSLock` (see `StubEngine`, `StubTransport`).
- **SSE parsing is byte-level on purpose.** Do not "simplify" it to
  string-splitting; chunk boundaries tear UTF-8 and lines otherwise. Tests
  slice fixtures into 5–7-byte chunks to prove this.
- **Tool-call arguments stream as JSON fragments.** Accumulate per index;
  Anthropic flushes on `content_block_stop`, OpenAI-compatible on `[DONE]`.
  Malformed accumulated JSON degrades to `{}` input, never a crash.
- **`AsyncThrowingStream` + inner `Task`** needs
  `continuation.onTermination = { _ in task.cancel() }` or cancelled
  consumers leak work.
- **GRDB `update()` throws if the row is missing** — stores use `save()`.
- **FTS5 MATCH breaks on user punctuation** — always go through
  `sanitizeFtsQuery`; recall falls back to recent-k when FTS yields nothing.
- **Engram schema compatibility matters**: `memories` columns must stay
  compatible with the Dart DB for the future import. Don't rename them.
- **SphereCore must not import SwiftUI/UIKit** — UI lives in `SphereUI`.
  This keeps `swift test` fast and the core portable to Watch/Widget.

## What's next (in order)

1. **Xcode app project** (plan Phase 2): App target (iOS 17+) + Widget +
   Watch targets depending on the `SphereCore` package. Wire the composition
   root: `AppDatabase(path:)` + `EngramStore(path:)` in Application Support,
   Keychain-backed `APIKeyStore` (`kSecAttrSynchronizable`),
   `FileOfflineCache`, one `AgentService`, stores per enabled sphere,
   `SphereToolRegistry(tools: stores.flatMap(\.tools))`.
2. Shell: TabView, onboarding, Settings (4 providers), Profile, String
   Catalog from the ARB files (`sphere/lib/l10n/*.arb`).
3. Home tab, then spheres wave 1 (Health → Learning → Career → Finance →
   Goals screen already exists), wave 2, chat, integrations — per the plan.
4. iCloud sync (Phase 8) and Engram v2 (Phase 9) are post-launch updates;
   do not start them ad hoc.

## Testing & CI

- `cd SphereCore && swift test` — full suite, runs on macOS, no simulator.
- CI is not set up yet (Phase 0 leftover): add a GitHub Actions workflow
  running `swift test` on macOS when the repo goes to GitHub.
