# Expansion plan — architecture for parity + novel features

Scope: everything in [BACKLOG.md](BACKLOG.md) — Flutter-parity gaps, all
per-sphere gems, and the seven cross-cutting identity features (N1–N7).
This document defines HOW they land in the existing code without breaking
the golden template, the tests, or the UI.

Companion docs: `HANDOFF.md` (add-a-sphere recipe, pitfalls),
`../../sphere/planning/IOS_REWRITE_PLAN.md` (original phases; Phases 8–9
CloudKit/Engram-v2 remain post-launch and are NOT expanded here).

---

## 0. Ground rules (unchanged)

- Golden template holds: `@MainActor @Observable` store on GRDB, additive
  migrations, agent tools on the store, tests for every public API.
- SphereCore stays UIKit/SwiftUI-free; platform services enter via
  protocols injected from the app target.
- Engram write paths stay network-free. LLM calls only through
  AgentService with the user's own key.
- One deliberate deviation from Flutter parity: **no per-service OAuth**
  (Strava/Oura/Fitbit/Spotify/LinkedIn/Reddit). HealthKit is the wearable
  layer by plan. Do not port the "Connected services" settings section.

## 1. Foundation changes (do these first — everything else leans on them)

### 1.1 Databases move to the App Group

Interactive widgets and App Intents (C2/C3) run in extension processes and
must WRITE (log water from the widget). The DBs currently live in
Application Support, invisible to extensions.

- New canonical location: `group.app.sphere.shared/Databases/sphere.db`
  (+ `sphere.engram.db`).
- `AppContainer.init`: if the App Group container is available and the old
  path exists but the new one doesn't → move `db`, `-wal`, `-shm` files,
  then open at the new path. Unsigned/CI builds (no App Group) keep the
  Application Support path — same guarded-nil pattern as
  `WidgetSnapshotStore`.
- Cross-process safety: extensions open a short-lived GRDB connection
  (open → write → close), WAL mode, `busyTimeout` set. Extract the
  water/mood/meditation quick-log SQL into `QuickLogSQL` (SphereCore) so
  the store methods AND the intents share one implementation — no drift.

### 1.2 Notification Engine (C1) — generalize BirthdayReminders

- SphereCore: `NotificationPlan` value type (stable id, category, trigger,
  title/body keys) and per-feature pure builders
  (`Medication.notificationPlans()`, `Plant.wateringPlan()`,
  `Subscription.renewalPlan()`, bedtime from `RestSchedule`, water cadence,
  morning brief, habit weekday reminders, check-in nudges). Pure functions
  → unit-testable without UNUserNotificationCenter.
- App target: `NotificationEngine` — one idempotent sync (fetch pending,
  diff by id, add/remove), permission requested lazily on first enabled
  category. `BirthdayReminders` becomes the first migrated client.
- Per-category opt-in toggles persisted in the profile
  (`notificationPrefs` JSON, migration `profile-v2`), surfaced in a new
  Settings "Notifications" section. Default: everything OFF except
  birthdays (current behavior).

### 1.3 Screen anatomy rule (the no-clutter law)

Every sphere screen follows a fixed skeleton so 40+ new lists don't bloat
anything:

1. **Hero card** — the sphere's one number/gauge + 2–3 stats.
2. **Primary sections** — at most three inline sections (the daily loop).
3. **"More" section** — plain `NavigationLink` rows to detail pages for
   every secondary list (Medications, Doctors, Debts, Appliances…).
4. Optional **AgentInsightCard** footer (see 4.5).

New shared scaffold in SphereUI: `CRUDListScreen` — generic list + swipe
delete + add-sheet + empty state, parameterized by row view and form
fields. Every parity CRUD list is an instance, not bespoke code.
**Refactor HealthScreen first** (it already exceeds the rule): move
Medications, Lab results, Workouts into drill-down pages; keep metrics
grid, water, weight inline.

### 1.4 profile-v2 migration

Adds: `notificationPrefs` (JSON), `wellbeingMode` (normal/sick/vacation +
until date), `vacationDaysPerYear`, `lockEnabled` mirror flag.

## 2. Trust pack (C6/C7/N7) — small, ship early

- **App lock**: `LockGate` view over the root in `SphereApp`, LAContext
  Face ID on `scenePhase == .active`, `Prefs.appLock` toggle in Settings.
- **Export**: `DataExporter` (SphereCore) walks all GRDB tables → one
  versioned JSON; `ShareLink` in Settings. Import is explicitly v2.
- **Privacy screen**: static Settings page — "local-first, your data never
  leaves the device except to the LLM provider you configured with your
  own key." Also one line in onboarding's last step.

## 3. Daily-loop pack

### 3.1 Universal quick capture (N1)

`SphereCore/Capture/`:
- `CaptureRuleParser` — tier 1, offline, locale-aware (en/uk) regex for
  the high-frequency logs: water, mood N, weight, "spent X on Y",
  meditation/workout minutes, gratitude. Returns `[LLMToolCall]`-shaped
  intents executed through the existing `SphereToolRegistry`.
- Tier 2 — if no rule matches and an API key exists: one-shot
  `AgentService` call, temperature 0, full registry, routing system
  prompt. Same execution path.
- `CaptureResult` = executed tool confirmations (existing confirmation
  strings) rendered as chips.

UI: toolbar `+` on Home and Spheres tabs → sheet: text field, mic button
(reuse `SpeechDictation`), result chips. Share/Action extension comes
after 1.1 (writes via App Group DB + `QuickLogSQL`). Watch quick-capture
rides the existing `WatchCommand` channel later.

### 3.2 App Intents + interactive widgets + Siri (C2/C3)

- `Sphere/Sources/Intents/`: `LogWaterIntent`, `LogMoodIntent`,
  `LogMeditationIntent`, `OpenQuickCaptureIntent`, `GetLifeScoreIntent`
  (reads the widget snapshot). Shared with the widget target.
- Widget medium family gains `Button(intent:)` water/meditation buttons;
  after write, intent refreshes the snapshot counts it owns and calls
  `WidgetCenter.reloadAllTimelines()`.
- App Shortcuts provider registers Siri phrases (en/uk).

### 3.3 Two new one-tap logs (feed the correlation engine)

- **Energy 1–5** (Health, `health-v3`) and **meal quality 1–5** (Health,
  same migration) — day-keyed, same shape as mood. Deliberately NOT
  calorie counting.
- **Gratitude** (Mindfulness, `mindfulness-v2`): 1–3 short lines, evening
  prompt via Notification Engine; entries also become Engram notes.
- **Affirmations** (parity): static seed list (en/uk) + daily pick card on
  MindfulnessScreen; user can add their own (same table).

### 3.4 Forgiveness (N4)

`SphereCore/Wellbeing/StreakPolicy.swift`:
- `WellbeingMode` from profile-v2; `StreakPolicy.effectiveStreak(dates:,
  pausedIntervals:)` — paused days are skipped, not failed.
- All streak call-sites route through it (meditation streak, detox streak,
  habit streaks, future reading streak).
- Life Score during pause: sphere scores freeze at the last pre-pause
  value and Home shows a "paused — get well" badge; FocusBuilder drops
  guilt-flavored items (meditation/steps/detox) while paused.
- UI: one toggle card on Home when activated from Profile ("I'm sick /
  on vacation until <date>").

### 3.5 Haptics + undo + empty states (C11/C12)

- `.sensoryFeedback` on quick logs; snackbar undo for swipe deletes
  (extend `CRUDListScreen` once, everyone inherits).
- Empty state = part of `CRUDListScreen` and hero cards: friendly line +
  one-tap "add first…" action.

## 4. Intelligence pack (the moat)

### 4.1 Correlation engine (N2)

`SphereCore/Insights/`:
- `DailySeries { metricID, displayName, values: [DayKey: Double] }`;
  stores expose theirs via `DailySeriesProviding` (mood, stress, sleep
  hours, workout minutes, water, meditation minutes, hobby minutes, daily
  spend, energy, meal quality; steps require caching the day's HealthKit
  value — `daily_metrics` table in `health-v3`).
- `CorrelationEngine.compute(series:)` — Pearson r over aligned day pairs
  + one-day-lag variant (yesterday's X vs today's Y, for sleep→mood).
  Report only |r| ≥ 0.3 with n ≥ 10 overlapping days. Pure, fully
  unit-tested with synthetic series.
- Phrasing templates are non-causal by design: "on days you X, Y tends to
  be higher/lower."
- Storage: `insights` table (`insights-v1`): metric pair, r, n, phrase,
  computedAt. Recomputed on background (with Engram maintenance) at most
  weekly.
- Surfacing: "Insight of the week" card on Home (below the brief), the
  weekly review, and a one-line footer on the two involved sphere screens.

### 4.2 Proactive nudges (N3)

`SphereCore/Nudges/`: `NudgeRule` = pure function over store snapshots →
`[Nudge]` (id, category, copy, cooldownDays). v1 rules: stress ≥ threshold
3 days & no meditation; budget ≥ 90% before day 24; contact staleness;
plant ≥ 2 days overdue; sleep debt > 5h/week; streak-about-to-lapse
(evening). Ledger table `nudges-v1` enforces per-rule cooldown and a
global cap of one proactive notification per day. Delivery through the
Notification Engine; evaluated in `AppContainer.loadAll` and on
background refresh. Every rule: unit tests for fire/no-fire/cooldown.

### 4.3 Weekly review (N5) + Life Wheel (N6)

- `reviews` table (`reviews-v1`): type (weekly/monthly/lifeWheel),
  periodKey, markdown content, selfRatings JSON.
- `WeekDigestProviding` — each store returns 2–4 factual lines for the
  week; `WeeklyReviewBuilder` assembles digests + top correlation +
  streaks, `AgentService` streams the narrative + one reflective
  question. Saved as a review row and an Engram note.
- Life Wheel: quarterly screen — 12 sliders (1–10) → radar/bar comparison
  (Swift Charts) against computed LifeScore; the delta line is the
  insight. Saved as a review row.
- Entry points: Goals screen gets the parity "Weekly review" / "Monthly
  review" buttons; Home shows a review card on Sunday evenings.

### 4.4 Agent-powered features (no new infra — prompts + existing tools)

- **Pre-meeting briefing** (Relationships): "Prep me for <contact>" button
  on the contact detail sheet → agent recalls Engram (`crossAgentRecall`
  by contact name) + contact facts → brief. 
- **Goal decomposition** (Goals): "Break this down" on a goal → agent
  proposes milestones + concrete actions; confirmation chips create tasks
  via existing sphere tools (career/home/health).
- **Interview prep** (Career): paste job description → agent generates
  questions, then mock-interviews in the existing chat UI.
- **Brag document** (Career): pure function — done tasks + achievements +
  period → markdown; ShareLink export. Agent polishes wording optionally.
- **Pattern analysis** (parity, all spheres): shared `AgentInsightCard`
  (SphereUI) — on-demand "Analyze my patterns" that feeds the sphere's
  summary tool output + related correlations to the agent. One component,
  every sphere screen's footer.

### 4.5 Finance intelligence

- **Safe-to-spend today**: pure computed — (month budgets − committed
  subscriptions − month-to-date spend) ÷ days left; hero number on
  FinanceScreen with drill-down explaining the math. Unit-test the edge
  cases (no budgets → hide).
- **Cooling-off wishlist** (`finance-v3`): wish item + createdAt; UI shows
  "ripens in 72h" state; после — "buy or drop?" prompt; optional nudge.
- **Subscription price-increase detection**: store last charged amount;
  flag when a new transaction matching the subscription differs upward.
- **Runway**: savings total ÷ average monthly expenses (needs ≥ 2 months
  of data; else hidden).

## 5. Parity CRUD (mechanical wave — all via `CRUDListScreen`)

| Sphere | Migration | New tables | Screen placement |
|---|---|---|---|
| Health | `health-v3` | doctors, symptoms, cycle_entries, energy, meals, daily_metrics | More → Doctors, Cycle (gated by profile gender), Symptoms; energy/meal as hero quick-taps |
| Finance | `finance-v3` | debts, investments, wishlist | More → Debts, Investments, Wishlist |
| Learning | `learning-v2` | courses, languages, flashcards, flashcard_reviews, study_sessions, learning_queue | More → Courses, Languages, Flashcards, Queue; weekly study chart on hero |
| Career | `career-v3` | skills, salary_entries, career_goals, one_on_ones | More → Skills, Salary, Career goals, 1:1 notes |
| Goals | `goals-v2` | anti_goals; goal.why column; habit.reminderDays | Why shown on goal card when stalled; Anti-goals under More |
| Mindfulness | `mindfulness-v2` | affirmations, gratitude_entries; session.note column | Affirmation + gratitude cards inline (daily loop) |
| Rest | `rest-v2` | naps, recovery_activities, vacation_ledger; detox schedule columns | Vacation balance on hero; More → Naps, Recovery menu |
| Travel | `travel-v2` | trip_journal, trip budget columns; country_facts (bundled asset) | Trip detail gains Journal + Budget tabs |
| Home | `home-v2` | appliances, utility_readings, renovation_projects, inventory; home_tasks.recurrence | More → Appliances, Utilities, Renovation, Inventory; recurring chores respawn on load |
| Creativity | `creativity-v2` | portfolio_items, project_sessions | Session timer on project detail; More → Portfolio |
| Hobbies | `hobbies-v2` | hobby_milestones; hobby.costTotal | Milestones on hobby detail; cost/session stat line |
| Relationships | `relationships-v2` | custom_dates; meeting_notes.quality; contact.source | Custom dates under contact detail |

Rules: every table = FetchableRecord/PersistableRecord model + store array
+ CRUD methods + tests; agent read-tools extended (snapshot JSONs gain the
new sections); write-tools added only where the Dart app had them or the
gem requires it (flag per commit, per the wave-2 convention).

Special mechanics in this wave:
- **Flashcards**: spaced repetition reusing Engram's Ebbinghaus math —
  `nextReview = f(easiness, repetition)` with the existing decay curve
  constants; review queue = due cards. 
- **Skill decay** (honest display): `effectiveLevel = level −
  decaySteps(lastPracticedAt)`, display-only, never mutates stored level.
- **Recurring chores**: `recurrence` (days) on home_tasks; on load, done
  tasks past their period respawn as open with new due date.
- **Pomodoro**: `PomodoroTimer` state machine in SphereCore (testable);
  UI on LearningScreen; ActivityKit Live Activity + Dynamic Island in the
  app target (guarded, later sub-step).
- **Legal** (parity): bundled markdown (ToS/privacy/licenses) in Settings
  → About.

## 6. Platform pack

- **HealthKit write-back (C4)**: new `HealthWriting` protocol (workout,
  mindful minutes, water, weight); `HealthKitService` implements;
  stores call the optional writer after local save. Mirror guard: never
  re-import what we wrote (tag samples with app source and filter).
- **Sleep auto-import**: `HealthSleepReading.sleepSamples(days:)` →
  `RestStore.syncFromHealthKit()` maps to SleepEntry (source flag,
  `rest-v2`), manual entries win on dayKey conflict. Runs on load +
  foreground.
- **Cycle**: HealthKit menstrual categories read into cycle_entries when
  authorized; manual entry otherwise.
- **Contacts import**: `CNContactPickerViewController` wrapper in the app
  target; maps name+birthday, dedupes by normalized name, `source =
  "contacts"`. Toolbar button on RelationshipsScreen.
- **EventKit (C8)**: `CalendarProviding` protocol in core; app-target
  `EventKitService`; today/tomorrow events → Meta Agent brief context +
  Goals "Upcoming events" card (parity). Settings toggle.
- **Global search (C5)**: `Searchable` protocol on stores (in-memory
  matching — all stores load at launch anyway); SearchScreen from the
  Spheres tab toolbar; journal content via existing Engram FTS. Core
  Spotlight donation is a later step.
- **MapKit visited map** (Travel): SwiftUI `Map` with shaded visited
  countries (bundled ISO-3166 centroid/polygon lite asset), fallback list
  stays.
- **Watch**: shopping list page (check off in the store) rides the
  existing snapshot+command channel; voice agent query = dictation →
  `WatchCommand.agentQuery(text)` → phone runs AgentService → reply via
  `sendMessage` reply handler.
- **Trip extras**: jet-lag bedtime shift plan (pure schedule math +
  Notification Engine); offline country card from the bundled asset;
  photo memories = PhotosPicker date-range fetch, stored as asset ids.

## 7. Home tab final layout (fixed order, prevents pile-up)

1. Greeting + Life Score ring (+ paused badge when in wellbeing mode)
2. Weather bar (fixed mini-forecast styling)
3. Quick-actions row — horizontal chips: + Capture, water, mood, gratitude
4. Meta Agent brief card (regenerate + location/calendar toggles in the
   card's ellipsis menu — parity without clutter)
5. Insight of the week (only when one exists)
6. Today's Focus
7. Weekly review prompt card (Sunday evening only)

Settings final sections: AI Providers · Notifications · Privacy & Data
(lock, export, privacy page) · Appearance · My Spheres · About (+ Legal).

## 8. Delivery waves

> **Superseded by [ROADMAP.md](ROADMAP.md)** — the canonical, dependency-
> sorted build order (Stages 0-9) that folds in the AI decision, the cycle
> work, and the competitive gems. This wave table is kept as the coarse
> rationale; execute against ROADMAP.

| Wave | Content | Exit criteria |
|---|---|---|
| **A. Foundations** | 1.1 DB→App Group, 1.2 Notification Engine (+BirthdayReminders migrated), 1.3 CRUDListScreen + Health refactor, 1.4 profile-v2, §2 trust pack | tests green; widget still works on signed build; no data loss on upgrade (migration test) |
| **B. Daily loop** | 3.1 capture (rule tier), 3.2 intents+widgets+Siri, 3.3 energy/meal/gratitude/affirmations, 3.4 forgiveness, 3.5 haptics/undo/empty | log water from widget & Siri; capture parses uk/en samples |
| **C. Parity CRUD** | §5 sphere by sphere (health → finance → learning → career → goals → mindfulness → rest → travel → home → creativity → hobbies → relationships), §7 Home/Settings layout, Legal | every list CRUD-tested; screens obey anatomy rule |
| **D. Intelligence** | 4.1 correlations, 4.2 nudges, 4.3 reviews+wheel, 4.4 agent features, 4.5 finance intelligence | correlation engine unit-proven; ≤1 proactive nudge/day enforced |
| **E. Platform** | §6 all items, capture share-extension, tier-2 LLM capture, Pomodoro Live Activity | sleep import replaces manual logging; contacts import round-trip |
| **F. Polish** | SphereUI uk localization (C9), Spotlight, watch voice, remaining P3s | uk render verified; final code review |

Wave order rationale: A unblocks B/E technically; B changes daily
retention immediately; C is mechanical volume (safe on Opus, per the
handoff recipe); D is the differentiator and needs C's data breadth;
E leans on entitlements and A's DB move.

## 9. AI access model: on-device first, then subscription / API keys

> **DECISION (2026-07-04):** The product ships **free on-device AI as the
> primary path — a choice of up to 5 models** (Apple's built-in Foundation
> Models model + ~4 curated downloadables). **Connecting a Claude / ChatGPT
> API key stays as an OPTIONAL power tier.** Consequence: the subscription /
> OAuth gray-zone work (§9b) is **deprioritized** — plain BYO API key is the
> only cloud path we build; §9b stays as reference only, to revisit if an
> official partner program opens. No user is ever required to have a key.

The strategic reframe: **the app should be free and useful with NO key, NO
account, and (ideally) NO download.** API keys become the power-user opt-in,
not the entry ticket. This is possible because our agent's job is
orchestration — route a sentence to the right sphere tool, write a short
brief — not frontier reasoning. A 1-3B on-device model is enough; the hard
part is reliable tool-call JSON, which constrained decoding solves.

### 9.0 The floor: most of the app needs no model at all

Weather, HealthKit, geolocation, Life Score, Today's Focus, cycle
predictions, correlations, budgets, streaks — all deterministic Swift. The
LLM is only the *concierge* layer: conversational chat + the daily brief +
free-text quick capture. So even a zero-AI user gets ~90% of the value, and
the rule-based capture parser (§3.1 tier 1) handles the most frequent logs
("coffee 4.50, mood 4") with no model. Design so the AI is additive, never a
gate.

### 9.1 Tiered AI, cheapest-capable first

`AIBackend` selected in Settings, resolved at runtime by capability:

- **Tier 0 — Apple on-device (default when available).** The Foundation
  Models framework (iOS 26+) exposes Apple's ~3B on-device model with
  **guided generation (constrained decoding) + tool calling**, no key, no
  download, fully private, on Apple-Intelligence devices (iPhone 15 Pro+ /
  A17 Pro+, M-series). This is the ideal default: zero setup, and guided
  generation makes 3B tool-calling reliable enough for our tight per-sphere
  toolsets. Fastest to ship (native Swift API). In 2026 the same framework
  can also route to Private Cloud Compute and third-party clouds — but we
  keep our own engines for cross-provider control.
- **Tier 1 — Downloadable small models (choice + reach).** For devices
  without Apple Intelligence, or users who want to pick, a **Models** screen
  offers 3-5 curated models to download/try/delete, each with size · RAM ·
  speed badges. Run via **MLX Swift** (Apple's recommended on-device runtime)
  or the `LocalLLMClient` Swift package (wraps llama.cpp + MLX). All Q4
  (4-bit) to fit mobile RAM. Candidate line-up:
  | Model | ~Size (Q4) | Note |
  |---|---|---|
  | SmolLM2-1.7B-Instruct | ~1.0 GB | smallest/fastest, basic |
  | Qwen2.5-1.5B-Instruct | ~1.0 GB | strong tool-use per byte |
  | Gemma-2-2B-it | ~1.6 GB | best quality/size balance |
  (Decision 2026-07-06: the catalog is capped at small models — ≤ ~2.6B
  params / ≤ 1.6 GB download; larger candidates like Llama-3.2-3B and
  Phi-3.5-mini were dropped.)
- **Tier 2 — Bring-your-own cloud (power).** OpenRouter only (decision
  2026-07-06): one key covers Claude / GPT / Gemini / everything else, so the
  direct Anthropic/OpenAI/Gemini engines were removed.

Resolution order at launch: user's explicit choice → else Apple FM if
available → else a downloaded model if present → else rule-based capture only
(+ a soft nudge that adding a model/key unlocks chat & brief).

### 9.2 Architecture fit (additive — the loop doesn't change)

Our LLM layer is already abstracted (`LLMProviderID`,
`OpenAICompatibleEngine`, `AgentService` tool loop, `ChatSession`). On-device
is **one or two new engines** behind the same seam:
- `FoundationModelsEngine` (wraps `LanguageModelSession`; map our
  `LLMTool` definitions to FM `Tool`s and our JSON schema to guided-generation
  `@Generable` types; stream tokens as today).
- `LocalModelEngine` (MLX / LocalLLMClient; enforce tool-call JSON via
  constrained decoding / grammar; expose the same streaming + tool-call
  assembly the OpenAI-compatible engine already produces).
`LLMProviderID` gains `.appleOnDevice` and `.localModel(id)`. AgentService,
SphereTools, the brief, capture — all unchanged. This is the same "add an
engine" move the engine seam was designed for.

### 9.3 Model manager (new, small subsystem)

`SphereCore/LLM/Local/`: `ModelCatalog` (curated list + metadata),
`ModelDownloader` (Wi-Fi-gated, resumable, background URLSession, checksum,
delete, disk-space guard), `InstalledModelStore`. Settings **Models** page:
per-model download/cancel/delete, size + RAM-fit badge (warn if the device
RAM can't hold it), pick-active, tiny "test" prompt. Downloads never run on
cellular by default; models live in Application Support (excluded from
iCloud backup).

### 9.4 Honest constraints (why this is a real engineering task)

- **Tool-calling accuracy** at 1-3B is below Claude/GPT. Mitigate:
  constrained decoding (mandatory), tight per-sphere toolsets (we already
  scope tools per sphere), few-shot tool prompts, and a retry-once on
  malformed JSON. Apple FM's guided generation largely removes this for
  Tier 0.
- **Device fragmentation.** Apple FM needs iPhone 15 Pro+. A 3B Q4 model
  strains < 8 GB devices (jetsam). Gate the catalog by device RAM; default
  low-RAM devices to a 1.5B or to rule-based + optional cloud.
- **Never in extensions.** Widget/watch quick-logs must stay rule-based —
  loading a 1 GB+ model in an App Extension will be killed for memory. The
  agent runs only in the foreground app (already our model for chat/brief).
- **UX cost.** 1-2 GB downloads (Wi-Fi, resumable, deletable); brief/chat
  quality is "good summary" not "brilliant"; keep briefs short, stream,
  allow cancel; watch battery/thermals on long generations.
- **No web/deep research on-device** — fine, we already fetch weather/data
  via direct APIs, not through the LLM.

### 9.5 Positioning payoff

"Free, private, on-device AI — no account, no key, nothing leaves your
phone" is a genuine differentiator and slots straight into the N7 privacy
positioning and the research finding that CRM/health/journal users demand
local-first. It also removes the single biggest onboarding wall (asking a
non-technical user for an API key).

---

## 9b. Provider auth: subscription sign-in alongside API keys — DEFERRED (reference only)

> Per the §9 decision, this is **not** on the build path. Kept for reference
> if Anthropic/OpenAI open an official third-party subscription program. The
> shipped cloud tier is plain BYO API key (already implemented). Do not start
> the OAuth work without a confirmed, ToS-clean partner program.

Goal: connect Anthropic / OpenAI / Gemini via the user's existing chat
subscription, not only a developer API key. (OpenRouter stays key-based
by decision.)

### Reality check (2026-07, verify before each release)

- **Anthropic**: Pro/Max OAuth tokens are ToS-restricted to Claude Code /
  claude.ai. There IS an official third-party surface ("connect app to
  Claude account", billed to prepaid *extra usage credits* since early
  2026) — but it requires enrollment in Anthropic's partner program.
  Action: apply for the program; ship behind a flag.
- **OpenAI**: ChatGPT sign-in (Codex-style OAuth) officially works only
  inside Codex tooling; third-party subscription routing is a ToS gray
  zone. Flag OFF by default until OpenAI opens it.
- **Gemini**: Google-account OAuth exists via Gemini CLI/Code Assist free
  tier; equivalent third-party use is likewise not officially sanctioned.
  Flag.
- Consequence: architecture ships NOW, flags flip per provider the day a
  program/policy opens. Never ship a default-on gray-zone auth path —
  App Store rejection + user account bans are the downside.

### Architecture (provider-agnostic, additive)

- `SphereCore/LLM/Auth/`:
  - `ProviderCredential` — `.apiKey(String)` | `.oauth(OAuthTokens)`
    (access, refresh, expiry, scopes), Codable, one Keychain item per
    provider (extends `KeychainAPIKeyStore` → `CredentialStore`; legacy
    plain-key items read as `.apiKey` — no migration needed).
  - `OAuthClient` — PKCE authorize-code flow, pure request builder +
    token exchange; the browser session enters via a `WebAuthPresenting`
    protocol (app target implements with `ASWebAuthenticationSession`).
  - `TokenRefresher` — single-flight refresh on 401/expiry, updates the
    Keychain, retries the request once.
- Engines change one seam: instead of a raw key string they take
  `credential: () async throws -> ProviderCredential` and set
  `Authorization: Bearer` vs `x-api-key` accordingly. Everything else
  (SSE, tool loop) untouched.
- `ProviderAuthCapability` registry: per provider, which methods are
  available (`.apiKey` always; `.subscription` behind a remote-config-less
  compile-time flag for now).
- Settings UI (see §10): per-provider page with a method segment —
  "Sign in with <Provider>" button (only when capability on) or key field.

## 10. Shell tabs review — Home, Settings, Profile

### Settings (biggest debt of the three)

Add:
- **Per-provider detail pages** instead of four bare SecureFields:
  status badge (Active / Configured / Off), auth method (key now,
  subscription per §9), **Test connection** button (one cheap models/list
  call → ✓/error), **model picker** per provider (sensible defaults +
  custom id field).
- **Explicit active-provider picker.** Today "first configured top to
  bottom" is invisible magic — make it a visible selection row.
- Planned sections from §7: **Notifications**, **Privacy & Data**
  (Face ID, export, privacy explainer), **About** (version, Legal
  markdown, acknowledgements).
- **Language row** deep-linking to per-app language in system Settings
  (iOS handles per-app locale natively; zero custom UI).
Change:
- **My Spheres** → sub-page combining toggles WITH drag-to-reorder (today
  reorder hides in the Spheres tab edit mode; one place for both).
Remove: nothing — the tab is under-built, not over-built.

### Profile

Add:
- **Avatar** (PhotosPicker, local file, feeds Home greeting) — parity.
- **About me** free-text bio — parity, and the highest-value agent
  context field of all.
- **Location/city** (manual text) — weather fallback when location
  permission is denied + travel/agent context.
- **"What agents know about me"** preview card rendering
  `profile.agentContext` — transparency builds trust in the whole
  agent concept (pairs with N7).
- **Wellbeing mode** control (sick/vacation until <date>) + vacation-days
  allowance — natural home for §3.4 and the Rest ledger setting.
Change:
- Persist on field commit/debounce, not only `onDisappear` (an app kill
  mid-edit loses the form today).
Remove: nothing; blood type stays (health context parity).

### Home

Add (final order already in §7): quick-actions row, insight card, weekly
review card, paused badge, `.refreshable` pull-to-refresh.
Change:
- **Meta Agent keyless card → tappable CTA** deep-linking to Settings →
  Providers (today it's inert text).
- **Today's Focus rows → deep-link** into their sphere screens (inert
  today); swipe-to-complete where the item is a completable task.
- **Best/needs mini-glyphs under the Life Score ring**: at that size the
  three tiny emoji+arrows read as noise — replace with the watch-style
  colored chips ("↑ Finance ↓ Career") under the greeting, or drop.
Remove: the tiny under-ring glyph row (superseded by chips).

## 11. Competitive research → concrete features

Sourced from a 2025-2026 scan of the category leaders per sphere (reviews,
Reddit, forum wishlists). The consistent finding: **users are drowning in
loggers and starving for insight**; the recurring complaint is "stop making
me categorize/log — tell me what changed and what to do." Sphere's 12-sphere
+ on-device-agent shape is exactly the whitespace none of these single-purpose
apps can reach. Items below fold into the waves; ★ = highest signal.

### Home tab — the dashboard becomes the product

The Home tab is where the cross-sphere moat is visible. Beyond making focus
items tappable (done), it should become a true daily cockpit:

- ★ **Daily open + shutdown ritual** (Sunsama's most-praised feature,
  generalized): a 2-minute AM setup card (today's top 3 across spheres,
  spend plan, one thing to learn/meditate) and a PM "close the day" review
  that marks what got done and gives psychological completion. This is a
  retention ritual no competitor does *across* life domains. → Wave D, ties
  the Weekly review (N5).
- ★ **One adaptive "Today" verdict** (Bevel's readiness + RISE's energy
  schedule): a single line — "You're well-recovered; best focus window
  9-11am; wind down 22:30" — computed from sleep/HRV/stress/calendar. Let
  the user rate how they *actually* felt so it self-corrects (RISE's #1
  failure was a schedule that never adapted). → Wave D + §6 HealthKit.
- **Free-to-act numbers row**: discretionary money (safe-to-spend),
  uncommitted time today, reviews-due count — the "you're fine, here's
  your room today" signal. → Wave D.
- Home already planned: quick-actions row, insight card, paused badge,
  pull-to-refresh (done).

### Cross-sphere identity thread (the meta-insight from ALL clusters)

Every winning app treats tracking as **identity/taste-building**, not
spreadsheets: Finch's pet, Letterboxd's diary, Atoms' "votes for who you're
becoming", Bearable's experiments. Sphere's answer:

- ★ **N-of-1 experiments / "what changed"** (Bearable's adored feature,
  generalized cross-sphere): "Cut caffeine after 2pm for 2 weeks" → the
  correlation engine (§4.1) reports the measured effect on sleep AND mood
  AND spend. Turns passive logging into personal science. → extends Wave D.
- ★ **"Year in Sphere" recap** (Strava's Year-in-Sport / Spotify Wrapped):
  a shareable, delightful annual/seasonal cross-sphere story. Critical
  lesson from Strava's 2025 backlash: **keep it FREE and shareable** — it's
  the virality engine. → Wave F.
- **Momentum over percentage** (Finch/Atoms): where a cold % is shown,
  offer a warm momentum/"becoming" framing; pairs with forgiveness (N4).

### Per-sphere steals (fold into the §5 CRUD wave and Wave D)

- **Health** — ★ adaptive readiness verdict (above); user-run experiments;
  "kind" non-punitive framing (Gentler Streak: *prescribe* rest days rather
  than guilt). Avoid competitors' fumble: never paywall the core insight.
- **Rest** — ★ **energy schedule / peak-focus windows** + sleep-debt number
  (RISE), self-correcting against felt-energy ratings; rock-solid HealthKit
  sleep import (§6) since flaky tracking is the #1 competitor complaint.
- **Mindfulness** — ★ **mood-adaptive session pick** (the Calm/Headspace
  gap: 70% churn from "same tone every time, no adaptation"): choose/generate
  today's micro-intervention from logged mood + HRV. Cheap with our agent.
- **Finance** — ★ **safe-to-spend** (already §4.5) is literally the
  most-requested number; ★ **subscription radar** (Rocket Money): auto-flag
  forgotten/renewing/price-changed subscriptions from the transaction feed;
  proactive "what changed" ("dining up 40% this week") over manual
  categorizing (Copilot). 
- **Career** — ★ Sunsama **shutdown ritual** (folds into Home ritual);
  "peak productivity window" insight ("your best deep-work is 9-11am") from
  task-completion timestamps; natural-language quick capture (Todoist).
- **Learning** — ★ **daily resurfacing** of your own highlights/quotes via
  Engram's Ebbinghaus curve (Readwise — already §5); **DNF-aware
  recommendations** (StoryGraph: model taste from what you *abandoned*, not
  just finished) — apply to books AND skipped tasks/ignored categories;
  reading stats/diary as taste profile.
- **Goals/Habits** — ★ **streak forgiveness/freeze** (N4 — the single
  most-requested fix across Streaks + Habitica; users quit after a reset);
  ★ **identity-based framing** (Atoms: habit = vote for an identity) +
  habit snoozing; drop any hard habit cap (Streaks' 24-limit is a top
  complaint).
- **Hobbies** — Letterboxd-style **diary + taste profile + lists**;
  free shareable yearly recap; keep it identity-flavored, not a log.
- **Creativity** — Milanote **freeform capture canvas** (messy pinboard for
  ideas) + the top wish competitors lack: **AI surfaces related
  ideas/inspiration** automatically (our agent + Engram recall); bridge
  "messy capture → structured project".
- **Travel** — ★ **auto-import booking emails** into itineraries (TripIt);
  **map everywhere** + planned-route-becomes-tracked-route (Polarsteps' #1
  gap); countries/places-visited **globe** as the trophy (§6 MapKit);
  shared-trip mode.
- **Home** — ★ **degrading-state chores** (Tody: tasks visibly decay and
  auto-suggest today's list) generalizing our recurring-chores plan;
  **fair-share** household split; warranty + **"who did I lend this to"**
  tracking (Sortly's abandoned consumer niche) at a household price.
- **Relationships** — ★ **pre-meeting context card** (Dex: "last talked 3
  weeks ago, her mom was sick, into climbing") triggered by calendar/geofence
  — already the marquee agent demo (§4.4); **cadence nudges with auto-snooze**
  (UpHabit: suppress the nudge if recent contact detected); message
  templates; relationship graph (mutual friends — the gap even Dex lacks).

### Privacy as positioning (recurs in every cluster)

Personal-CRM, health, and journal users explicitly ask for local-first /
private handling. Sphere already is — N7 (§2) turns that into a stated
selling point; especially resonant against cloud-CRM (Dex/Clay) and
data-hungry health apps.

## 12. Testing & risks

- Every pure engine (correlations, streak policy, capture rules, nudge
  rules, safe-to-spend, jet-lag plan, recurrence respawn, flashcard
  scheduling) gets exhaustive swift-testing suites — they are the moat.
- Migration test: open a v-previous fixture DB, run migrator, assert data
  intact (especially the App Group move).
- Extension-write test: simulate `QuickLogSQL` from a second connection.
- Notification plans: assert idempotent diff (no duplicate ids).
- Risks: App Group move (mitigate: copy-then-verify-then-delete);
  cross-process SQLite contention (short-lived connections, busy
  timeout); HealthKit write mirror loops (source tagging); nudge fatigue
  (global cap + cooldown ledger); screen bloat (anatomy rule is law).
