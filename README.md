# Sphere (iOS)

Native SwiftUI rewrite of [Sphere](https://github.com/TAIPANBOX/sphere) — a
Personal Life Intelligence System with 12 life-sphere AI agents and on-device
cognitive memory (Engram).

Rewrite plan: [sphere/planning/IOS_REWRITE_PLAN.md](https://github.com/TAIPANBOX/sphere/blob/main/planning/IOS_REWRITE_PLAN.md)

## Structure

- `SphereCore/` — SPM package: models, Engram memory, LLM engines, services.
  Pure Swift, testable with `swift test`, shared by App / Widget / Watch targets.

## Status

- [x] Engram v1.5 on GRDB — episodic memory, FTS5 + BM25 recall, access
  reinforcement, Ebbinghaus decay + pruning
- [x] LLM layer — Anthropic native + OpenAI-compatible engines (OpenAI,
  Gemini, OpenRouter), SSE streaming, tool-call assembly
- [x] Agent layer — AgentService (chat tool-loop, daily brief, insight with
  offline cache), SphereToolRegistry, sphere/meta prompts
- [x] Golden-template sphere (Goals) — @Observable store on GRDB, agent
  tools (add_goal / list_goals), Engram notes, SwiftUI screen in `SphereUI`
- [x] Health sphere — HealthKit behind `HealthMetricsProviding` (real
  `HealthKitService` + fake for tests), water/weight/workouts on GRDB,
  agent tools (log_water_glass, log_weight, get_health_today), screen with
  Swift Charts weekly steps (98 tests total). Secondary lists (medications,
  labs, cycle, doctor) still to port — simple CRUD per the handoff recipe.
- [x] Finance sphere — transactions feed, monthly budgets with over-budget
  detection, subscriptions with billing countdown, agent tools
  (add_transaction, get_finance_summary), screen (110 tests total).
  Secondary lists (accounts, debts, investments, savings) to port per the
  handoff recipe.
- [x] Learning sphere — books library (reading/queue/completed, page
  progress, quotes, notes) + skills tracker (1–5 levels, categories),
  list_books agent tool, screen (118 tests total). Secondary lists
  (courses, flashcards, languages) and the Pomodoro timer to port per the
  handoff recipe.
- [x] Career sphere — task manager (open/done/overdue, Today's Focus feed),
  active projects with deadlines, interviews pipeline, agent tools
  (add_career_task, list_career_tasks), screen (129 tests total). Secondary
  lists (achievements, career goals, network, salary, career skills) to port
  per the handoff recipe.
- [x] Home tab — Life Score (per-sphere formulas from the Flutter home tab),
  Today's Focus builder (urgency-ranked, with fallbacks), Open-Meteo weather
  (+ CoreLocation provider), HomeStore aggregating the sphere stores with
  streamed Meta Agent brief, HomeScreen (146 tests total). Wave-2 focus
  sources (birthdays, home tasks, rest/hobbies scores) join as those spheres
  are ported.
- [x] Agent chat — ChatSession state machine (streaming bubbles, tool
  confirmation chips, fresh bubble after tools, friendly error bubbles,
  history building with image placeholders) + ChatScreen (markdown bubbles,
  photo attachments via PhotosPicker, auto-scroll) (155 tests total).
  Voice input (SFSpeechRecognizer) lands with the app target.
- [x] Rest sphere — sleep log with recovery levels + Recovery Score
  (formula from the Flutter screen), sleep schedule with midnight rollover,
  digital-detox streak, anti-burnout work hours, weekend plans, agent tools
  (log_sleep, get_rest_summary — new; the Dart version had none), screen
  with sleep chart (166 tests total).
- [x] Travel sphere — trip planner with type-specific packing/document
  checklists, next-trip countdown, countries visited (dedup), dream list,
  agent tools (add_wishlist_destination, get_travel_summary — new), screen
  with trip detail checklists and flow-layout country chips (176 tests
  total).
- [x] Mindfulness sphere — meditation sessions with streak, day-keyed mood
  (1–5) and stress (1–10) check-ins, journal with Engram previews, all four
  Dart agent tools ported verbatim (log_meditation, log_mood,
  add_journal_entry, get_mindfulness_summary), screen with mood row,
  animated 4-7-8 breathing exercise, stress chart, journal (186 tests
  total). Affirmations list to port per the handoff recipe.
- [x] Home sphere — household tasks (overdue/due-today helpers for Today's
  Focus), plant watering with intervals, shopping list, agent tools
  (add_home_task, add_shopping_item, get_home_summary — new), screen
  (194 tests total). Secondary lists (appliances, inventory, renovation,
  utilities) to port per the handoff recipe.
- [x] Creativity sphere — creative projects (8 types, idea/in-progress/
  paused/completed, progress with lastWorkedOn stamping, collaborators) +
  idea capture, agent tools (capture_idea, get_creativity_summary — new),
  screen with inline idea capture (202 tests total). Portfolio and project
  sessions to port per the handoff recipe.
- [x] Hobbies sphere — hobby list with weekly targets/goals/equipment,
  session log with cascade delete, weekly-minutes windows (feeds the Life
  Score), agent tools (log_hobby_session with by-name matching that lists
  known hobbies on miss, get_hobbies_summary — new), screen (210 tests
  total).
- [x] Relationships sphere — contacts with birthday countdown (year
  rollover), check-in reminders, gift ideas/meeting notes, agent tools
  (add_contact, mark_contacted, get_relationships_summary — new), screen
  (218 tests total). **All 12 spheres ported.**
- [x] App target (iOS 17+) — XcodeGen project (`xcodegen generate` →
  `Sphere.xcodeproj`), AppContainer composition root (databases in
  Application Support, Keychain-backed API keys, one AgentService, 12
  stores, unified tool registry, per-sphere chat sessions, Engram decay on
  background), 4-tab shell (Home · Spheres grid with per-sphere chat ·
  Settings with provider keys · Profile), HealthKit/location/photos usage
  strings. Verified in the iOS Simulator.
- [x] Wave-2 cross-sphere wiring — LifeScore now scores 8 spheres
  (+ relationships/rest/hobbies formulas from Dart), Today's Focus includes
  contact birthdays and home-sphere overdue/due-today tasks, meditation
  check wired from Mindfulness, yearly birthday notifications at 09:00
  (UNCalendarNotificationTrigger, idempotent resync) (223 tests total).
- [x] Profile + onboarding + Settings — UserProfile shared-context model
  (`agentContext` woven into every agent's system prompt), ProfileStore on
  GRDB (single JSON row), 4-step onboarding flow (welcome → personal →
  dietary → spheres) gating first launch, full Profile editor (personal /
  body / dietary / allergies / conditions chips), Settings with provider
  keys + My Spheres toggles; grid shows only active spheres; birthday
  reminders defer their permission prompt until a contact has a birthday
  (230 tests total). Verified in the iOS Simulator.
- [x] Spheres tab — live per-sphere stat line + progress (eight reuse the
  LifeScore insight/score, four computed via SphereStat), drag-to-reorder
  persisted to the profile (`sphereOrder`, unknown spheres trail in enum
  order), row → sphere screen, bubble → agent chat (235 tests total).
- [x] Theme + currency preferences — Settings Appearance section
  (system/light/dark theme via `preferredColorScheme`, currency picker);
  `Currency` enum in SphereCore with locale-aware formatting drives the
  Finance screen (238 tests total). Verified system dark mode in the
  simulator.
- [x] Home-screen widget — WidgetKit extension (small: Life Score ring +
  best/needs chips; medium: + top-3 focus) reading a shared App Group
  snapshot the app writes after loadAll/background; store unit-tested,
  pipeline verified on a signed simulator build (241 tests total).
- [x] Apple Watch — watchOS app (Life Score ring + best/needs + top focus)
  and complications (circular gauge / rectangular / inline) fed by the phone
  over WatchConnectivity (`updateApplicationContext`); the watch persists the
  snapshot to its own App Group for the complication (243 tests total).
- [x] Localization (EN/UK) — app-shell String Catalog (tabs, sphere names,
  onboarding, Settings, Profile) with Ukrainian from the Flutter ARB;
  verified rendering under `-AppleLanguages '(uk)'`. Sphere screens
  (SphereUI package) still inline-English — same pattern, larger volume.
- [x] Voice input in chat — on-device `SFSpeechRecognizer` dictation
  (SpeechDictation in SphereUI, iOS-guarded); mic button in the chat input
  streams partial transcripts into the draft (243 tests total).
- [x] Health secondary lists — medications (taken toggle, dosage/
  frequency, reminders-ready) and lab results (value/unit/range, normal
  flag) on GRDB, surfaced in the agent snapshot (248 tests total).
- [x] Finance secondary lists — accounts (net-worth total) and savings
  goals (progress, add/withdraw) on GRDB, in the agent snapshot (252 tests).
- [x] Watch quick-logging — Water / 10-min meditation / mood (1–5) from the
  wrist over WCSession; phone applies to the store and pushes a fresh
  snapshot back (254 tests). Watch read + write both done.
- [ ] Remaining secondary lists (Finance debts/investments, Career/Learning);
  SphereUI screen localization; Watch voice agent queries

## Development

```bash
# Core (models, Engram, LLM, stores) — fast, no simulator
cd SphereCore && swift test

# App — generate the Xcode project first (it is gitignored)
brew install xcodegen
xcodegen generate
open Sphere.xcodeproj
```

## License

MIT
