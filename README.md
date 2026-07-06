# Sphere (iOS)

> **Your whole life, understood by agents that remember.** Twelve life-sphere AI
> agents, cross-sphere intelligence, and on-device memory — private by default,
> free without a key.

![CI](https://github.com/TAIPANBOX/sphere-ios/actions/workflows/ci.yml/badge.svg)
![Swift 6](https://img.shields.io/badge/swift-6-F05138.svg?logo=swift)
![Platform](https://img.shields.io/badge/platform-iOS%2017%20·%20watchOS%2010-1a1a1a?logo=apple)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Tests](https://img.shields.io/badge/tests-509%20passed-green)

Native SwiftUI rewrite of [Sphere](https://github.com/TAIPANBOX/sphere) — a
Personal Life Intelligence System.

---

## The problem

Your life is scattered across a dozen apps. A habit tracker here, a budget app
there, a notes app, a calendar, a health app, a reading list. None of them talk
to each other, so none of them can tell you the thing that actually matters:
*your sleep debt is why your spending crept up this week*, or *the weeks you
meditate are the weeks you hit your goals.*

And most of them punish you. Miss a day and the streak resets to zero. Open the
app and a cold **"38% complete"** stares back. That's why the average tracker is
abandoned inside two weeks.

**Sphere is one place that sees the whole picture — and is kind about it.**

---

## What Sphere does

Twelve life spheres — Health, Finance, Career, Learning, Relationships, Rest,
Hobbies, Travel, Mindfulness, Creativity, Home, Goals — each with its own
`@Observable` store, agent tools, and screen. On top of them sits a layer that
no single-sphere app can build:

- **Cross-sphere correlation engine** — day-keyed metrics across every sphere,
  surfacing honest patterns ("on days your sleep is higher, your mood tends to
  be higher — a pattern, not proof").
- **Proactive nudges** — one gentle, cooled-down suggestion a day, assembled
  from real context (stress streaks, budget pace, sleep debt, a thirsty plant).
- **Weekly narrative review + Life Wheel** — a warm recap and a feeling-vs-data
  gap chart across the twelve spheres.
- **N-of-1 experiments** — "cut caffeine after 2pm for two weeks," measured
  against the baseline across sleep, mood, and spend. Passive logging becomes
  personal science.
- **Adaptive "Today" verdict** — one line from sleep, stress, and energy, that
  self-corrects on how you actually felt.
- **Year in Sphere** — a free, shareable recap of your year across every sphere.
- **Forgiveness + momentum** — excused days bridge streaks; warm "building
  momentum" framing replaces the cold percentage.

Everything works with **zero setup and no account**. Rule-based quick capture
("water 2, mood 4, spent 12 on lunch") and every deterministic feature run with
no model at all.

## AI, three ways — free first

| Tier | Backend | Cost | Needs |
|------|---------|------|-------|
| Free | Apple Foundation Models (on-device) | Free | iPhone 15 Pro+ / iOS 26 |
| Free | Downloaded model (MLX, on-device) | Free | A recent device + a download |
| Power | OpenRouter (Claude · GPT · Gemini · …) | Your key | One OpenRouter key (optional) |

Nothing ever *requires* a key. The on-device paths keep your data on your phone.

---

## Architecture

```
SphereCore/            SPM package — pure Swift, no UIKit. `swift test`-able,
                       shared by every target.
├── Sources/SphereCore Models, 12 sphere stores (GRDB), Engram memory, LLM
│                      engines, agent service, insight/nudge/review/experiment
│                      engines, search, on-device model manager.
└── Sources/SphereUI   All SwiftUI screens (compiles on macOS too, for previews).

Sphere/                iOS app target (XcodeGen — project.yml).
SphereWidget/          Home-screen + Smart Stack widget.
Watch/                 watchOS app + complication + WCSession bridge.
```

- **Persistence:** [GRDB](https://github.com/groue/GRDB.swift) with additive
  migrations; one App Group container shared with the widget, App Intents, and
  watch.
- **Memory:** Engram v1.5 — episodic memory with FTS5/BM25 recall, access
  reinforcement, and Ebbinghaus decay.
- **LLM:** one OpenAI-compatible cloud engine (OpenRouter) behind a single
  `LLMEngine` seam, plus Apple Foundation Models and MLX-backed local models.
- **Sync:** CloudKit; wearables via HealthKit — no per-service OAuth.

## Build

```bash
# Core package — pure Swift, runs anywhere Swift does
cd SphereCore
swift build
swift test          # 509 tests

# App — generate the Xcode project, then build for a simulator
brew install xcodegen
xcodegen generate
xcodebuild -project Sphere.xcodeproj -scheme Sphere \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

The downloaded-model backend uses MLX, which needs a device GPU: the code
compiles for the simulator but runs inference only on a real device.

## Privacy

Local-first by design. Sphere data lives in on-device GRDB; the free AI paths
never leave the phone. API keys (optional) are stored in the iCloud Keychain and
used only when you pick a cloud model. Full data export (JSON) and a Face ID lock
ship in Settings.

## Status

All twelve spheres plus the intelligence, platform-integration, and polish
stages are built — see [docs/ROADMAP.md](docs/ROADMAP.md) for the full,
dependency-ordered plan and what remains (constrained on-device tool calling,
Spotlight donation, notification delivery of nudges).

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md). In short: `swift test` must stay green,
every public `SphereCore` API gets a test, and all repo content is in English.

## License

[MIT](LICENSE) © TAIPANBOX
