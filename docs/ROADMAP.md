# Build roadmap — the ordered sequence

This is the **canonical execution order**. It consolidates everything we
gathered into one dependency-sorted sequence: Flutter-parity gaps
([BACKLOG.md](BACKLOG.md)), best-in-class features from the competitive
research ([EXPANSION_PLAN.md §11](EXPANSION_PLAN.md)), the seven identity
features N1-N7, and the free-AI decision (§9). Architecture detail for each
item lives in EXPANSION_PLAN; this file is the "what, in what order."

Supersedes the Wave A-F list in EXPANSION_PLAN §8. Do stages top to bottom;
inside a stage, top to bottom. Each stage is a shippable increment with
green tests.

Legend: `[x]` done · `[~]` partly done · `[ ]` to do.

---

## Stage 0 — Done this session (baseline)

- [x] Home "Today's Focus" rows navigate to their sphere (value-based nav,
  shared `SphereRootScreen`).
- [x] Keyless Meta Agent card → tappable CTA to Settings; Home
  pull-to-refresh.
- [x] Weather mini-forecast redrawn with SF Symbols (was blurry emoji).
- [x] Menstrual/ovulation cycle tracking (health-v3): CycleEntry +
  CyclePredictor (phase, next-period, fertile window) + `log_period` tool +
  HealthScreen card gated to female profiles.

---

## Stage 1 — Foundations & trust (everything leans on this)

*Why first: extensions must be able to write; the notification backbone and
the screen-anatomy rule are prerequisites for later stages; trust features
are cheap and high-value.*

- [x] **DB → App Group move** (§1.1) — `DatabaseLocation.resolve()`:
  canonical `sphere.db` / `engram.db` in `group.app.sphere.shared/Databases`;
  copy-verify-delete of db+wal+shm; guarded-nil fallback for unsigned/CI.
  Verified: data (female profile + 3 cycles) survived the move. `QuickLogSQL`
  extraction deferred to Stage 3 (needed when the widget/intents write).
- [x] **profile-v2** (§1.4) — `notificationPrefs`, `wellbeingMode` (+until),
  `vacationDaysPerYear`, `appLockEnabled`; tolerant `decodeIfPresent` decoder
  (no GRDB migration; old JSON never breaks). Tests green.
- [x] **Notification Engine** (§1.2, C1) — pure `NotificationPlan` +
  `NotificationCategory` + builders (SphereCore, tested); app-target
  `NotificationEngine` idempotent sync; `BirthdayReminders` migrated to it;
  per-category opt-in in profile (default off except birthdays).
- [x] **CRUDListScreen scaffold + screen-anatomy rule** (§1.3) — generic
  `CRUDListScreen` (list + swipe-delete + add-sheet + empty state with
  "add first") and `MoreLink` in SphereUI; **HealthScreen refactored** to
  hero (metrics/cycle/water/weight) + a "More" section linking out to
  Medications / Lab results / Workouts drill-downs. `#if os(iOS)` guard on
  `navigationBarTitleDisplayMode` (SphereUI also compiles on macOS).
- [x] **Trust pack** (§2, C6/C7/N7) — `LockGate` Face ID app lock
  (`Prefs.appLock` + NSFaceIDUsageDescription); `DataExporter` JSON export
  (SphereCore, tested) + share sheet; `PrivacyScreen`; Settings gained
  Notifications + Privacy & Data sections.

**Done when:** widget still writes on a signed build ✅; upgrade loses no data
✅ (migration verified); Health screen obeys the anatomy rule ✅.

**Stage 1 COMPLETE.** 278 tests green; app builds, installs, launches.

## Stage 2 — Free AI, Tier 0 (the product promise: usable with no key)

*Why here: makes the app genuinely free and removes the onboarding wall;
small once foundations exist (one engine); lets every later feature be
demoed without a key.*

- [x] **FoundationModelsEngine** (§9.1 Tier 0) — Apple on-device model via
  the Foundation Models framework (app target, `#if canImport` + `@available
  iOS 26`, so SphereCore stays framework-free). `OnDeviceAI.makeEngineIfAvailable()`
  gates on `SystemLanguageModel.default.availability`. Streams text
  (`streamResponse`/`respond`). **v1 is text-only — no on-device tool
  calling yet** (emits text + `.endTurn`); tool-driven logging routes via
  rule-based capture (Stage 3) or a cloud key. Follow-up: FM guided-generation
  tool calling.
- [x] **Backend selection** (§9.1) — `AIBackend` (`.onDevice`/`.cloud`) in
  SphereCore; `AgentService.resolveBackend()` = explicit choice → free
  on-device → first cloud key → `noApiKey`. Injected `onDeviceEngine` +
  `preferredBackend` closures (SphereCore stays pure). 6 selection tests.
- [x] **Provider/Settings restructure** (§10) — "AI" section with an
  Assistant picker (Automatic / On-device (free) when available / the four
  cloud providers); keys moved to an "API keys (optional)" section; footer
  explains on-device is free/private. `Prefs.aiBackend` + `AppBackendPreference`.
- [x] **Onboarding** — welcome step now states "Free & private — runs
  on-device, no account or key needed."

**Done when:** a fresh install with no key can chat and get a daily brief on
an Apple-Intelligence device ✅ (arch in place; live generation needs Apple
Intelligence enabled on the device/sim); key entry is clearly optional ✅.
284 tests green; app builds/installs/launches.

## Stage 3 — Daily loop & capture (attack logging fatigue)

*Why here: directly targets the #1 churn cause (research); needs the App
Group (S1) and benefits from Tier-0 AI (S2).*

- [~] **Universal quick capture** (§3.1, N1) — DONE: tier-1 rule parser
  (en/uk) `CaptureRuleParser` → `QuickCapture.run` executes each fact via the
  tool registry (water/weight/mood/meditation/spend, multi-fact, uk decimal
  commas); `QuickCaptureSheet` (text + mic) + `+` on Home; `AppContainer.
  quickCapture`. 10 tests incl. end-to-end (3 stores mutated from one line).
  REMAINING: tier-2 agent routing for missed phrases, Share/Action extension,
  `+` on the Spheres tab.
- [~] **App Intents + interactive widgets + Siri** (§3.2, C2/C3) — DONE:
  `QuickLogSQL` (cross-process atomic writes to the shared App Group DB,
  tested; `HealthStore.incrementWater` now delegates to it) + `SharedDatabase
  Location`; App Intents `LogWater/LogMood/LogMeditation` + `SphereShortcuts`
  AppShortcutsProvider (Siri phrases). Build-verified; Siri/Shortcuts runtime
  needs a device. REMAINING: interactive **widget button** (`Button(intent:)`
  — the intent must be shared into the widget target).
- [x] **New one-tap logs** (§3.3) — DONE: energy 1-5 & meal-quality 1-5
  (Health, `health-v4`, day-keyed, `RatingSelector` card, `log_energy`/
  `log_meal` tools + snapshot + capture keywords); gratitude (Mindfulness,
  `mindfulness-v2`, inline card + Engram note); affirmations (10 seeds +
  custom, daily stable pick, card). 5 tests. (Gratitude evening notification
  deferred to when nudges land.)
- [x] **Forgiveness** (§3.4, N4) — DONE: `StreakPolicy` (excused days bridge
  streaks instead of breaking them, tested); `MindfulnessStore.currentStreak`
  routes through it with `excusedStreakDays`; `FocusBuilder` `isPaused` drops
  the daily-habit nags (meditation/steps/fallbacks) while keeping real
  commitments; profile gained `wellbeingSince` + `wellbeingExcusedDays`;
  `AppContainer.setWellbeing/applyWellbeing`; Profile "Wellbeing" control
  (Normal/Sick/Vacation + optional end date); Home "Recovery mode" badge.
  7 tests. (Life Score freeze deferred — suppressing nags + bridging streaks
  is the visible forgiveness.)
- [x] **Haptics + undo + empty states** (§3.5, C11/C12) — DONE: `.sensory
  Feedback` on RatingSelector taps, water buttons, quick-capture success;
  `CRUDListScreen` undo bar (`onRestore`, 4s) wired to Health's three lists;
  empty states already via CRUDListScreen (Stage 1). `+` also added to the
  Spheres tab.

**Done when:** log water from widget & Siri; capture parses uk/en samples;
sick-mode freezes streaks.

## Stage 4 — Home cockpit, Settings, Profile (the shell becomes the product)

*Why here: high daily visibility; some Home work already done; the daily
ritual is the cross-sphere retention hook.*

- [~] **Home** (§7, §11) — DONE: quick-actions row (💧 Water / 🧘 Meditate
  direct via capture + ➕ Capture, haptic + transient confirmation);
  best/needs redesigned into tappable colored chips under the greeting
  (tiny under-ring glyphs removed; `LifeScoreBadge` now ring-only "Life").
  Insight/weekly-review card slots deferred to S6 (they need that data).
- [x] **Daily open + shutdown ritual** (§11, Sunsama) — DONE: `DailyRitual`
  + `RitualTiming` (pure phase-from-time, tested) + `RitualStore` (`ritual-v1`,
  day-keyed); `HomeStore.todayHighlights()` for the evening review; Home
  `ritualCard` (morning ☀️ / evening 🌙, time-gated) → `RitualSheet` (morning:
  intention + commit to focus items; evening: what-you-did highlights +
  reflection → "close the day"). 8 tests.
- [x] **Settings** (§10) — DONE: Notifications, Privacy & Data, AI/Assistant
  picker; General section (Language row → system per-app settings; My Spheres
  sub-page `MySpheresScreen` combining toggles + drag-reorder); About section
  → `AboutScreen` (version, ethos, Privacy link, acknowledgements).
- [x] **Profile** (§10) — DONE: About-me bio + city (feed `agentContext`);
  "What your agents know about you" card; wellbeing control; **avatar**
  (PhotosPicker → downscaled JPEG in `AvatarStorage`, initials fallback);
  **persist-on-commit** (now also saves on `scenePhase == .background`, not
  just onDisappear).

**Stage 4 COMPLETE** (bar the S6-dependent insight/review Home slots). 317
tests green; app builds/installs/launches.

**Done when:** AM/PM ritual round-trips; Settings/Profile match §10.

## Stage 5 — Parity CRUD + per-sphere gems (the big mechanical wave)

*Why here: needs the anatomy rule (S1); large but mechanical (safe on the
conveyor); gem sub-items that need intelligence trail into S6.* Each sphere
= Flutter-parity secondary lists **plus** the researched gems, one migration
per sphere (§5 table). Order:

- [x] **Finance** (finance-v3) — DONE: debts + investments + wishlist (72h
  cooling-off, ripe/cooling row states) as `CRUDListScreen` drill-downs under
  a "More" section; **safe-to-spend today** hero (pure `FinanceMath`, tested);
  **subscription radar** (`upcomingRenewals`); **monthly category chart**
  (Swift Charts); `netWorth` (accounts + investments − debts); safe-to-spend
  + net worth in the agent snapshot. 10 tests. (Price-change detection needs
  charge history — deferred.)
- [~] **Learning** (learning-v2) — DONE: courses, languages, read/watch
  queue (done-toggle) as `CRUDListScreen` drill-downs; **flashcards with
  spaced repetition** (`SpacedRepetition` SM-2, the Ebbinghaus-curve inverse,
  tested) — review sheet (reveal → Forgot/Good/Easy grades reschedule),
  due-count card, manage list. 8 tests. REMAINING: Pomodoro (+Live Activity),
  daily resurfacing of own quotes/highlights, DNF-aware recs.
- [x] **Rest** (rest-v2) — DONE: naps + recovery-activities menu (personal
  effectiveness rating) as `CRUDListScreen` drill-downs; **vacation ledger**
  (used/left this year vs profile allowance, mark-today toggle); **sleep-debt**
  card (`SleepMath`, 7-night deficit vs goal, pure/tested). 7 tests. (Energy
  schedule / self-correcting deferred — needs HealthKit + felt-energy ratings.)
- [x] **Home sphere** (home-v2) — DONE: appliances (+**warranty radar**,
  expiring-soon card), utilities (readings + cost), renovation (budget/spent),
  inventory (+**"lent to"** tracking) as `CRUDListScreen` drill-downs;
  **recurring chores respawn** on completion (`HomeTask.recurrenceDays` +
  `RecurringChore.nextOccurrence`, wired into `toggle`, tested). 9 tests.
- [x] **Career** (career-v3) — DONE: skills (1-5), salary history, career
  goals, 1:1 notes (with talking points) as `CRUDListScreen` drill-downs;
  **brag document** (`BragDocument` pure builder → markdown of achievements +
  completed work, viewable + `ShareLink` export). 6 tests. (Interview prep
  needs the agent; peak-productivity needs task completion timestamps — both
  deferred.)
- [x] **Relationships** (relationships-v2) — DONE: **pre-meeting context
  card** (`MeetingPrep` assembles last-talked / upcoming dates / important
  info / notes / gift ideas — pure, tested; contact-tap detail sheet);
  custom dates (recurring, roll to next year); message templates (seeds +
  own, copy-to-clipboard); cadence nudge auto-snooze already inherent
  (`needsCheckin` resets on `markContacted`). 7 tests. (Agent-enriched
  briefing via Engram recall is a later enhancement.)
- [ ] **Health** (finish) — doctors, symptoms (+correlation later); HealthKit
  parts deferred to S7. (cycle/meal/energy already covered.)
- [~] **Mindfulness** — DONE: **Focus sessions + daily Discipline score +
  focus streak** (Tysh-inspired; focus logged as `.focus` meditation sessions,
  no migration; `DisciplineScore` pure/tested; `FocusTimerSheet` countdown);
  **breathing patterns** (4-7-8 / box / coherent, `BreathingPattern` + picker,
  generalized `BreathingExerciseView`). gratitude/affirmations in S3; session
  notes already existed. 6 tests. REMAINING: body-scan guide, mood-adaptive
  session pick (needs AI). Tysh app/website blocking + screen-time = Family
  Controls entitlement, separate phase if pursued.
- [x] **Travel** (travel-v2) — DONE: per-trip **journal**; **budget** (planned
  vs actual spent, over-budget flag); **jet-lag plan** (`JetLagPlan` pure —
  ~1h/day bedtime shift capped at the time diff, tested); **offline country
  card** (`CountryGuide` curated emergency/plug/note per country). 7 tests. All
  in the trip detail. (Auto-link spent → Finance, editable packing templates,
  photo auto-collect, MapKit visited map deferred.)
- [x] **Creativity** (creativity-v2) — DONE: **portfolio** (`CRUDListScreen`
  drill-down); **work-session timer** (count-up stopwatch → logs minutes,
  stamps project `lastWorkedOn`); **momentum card** (minutes this ISO week +
  7-day bar sparkline). 4 tests. (Freeform capture canvas + AI related-ideas
  deferred — idea capture already exists.)
- [x] **Hobbies** (hobbies-v2) — DONE: per-hobby **milestones** (progression
  checklist, tap-to-toggle); **cost/session** (gear spend ÷ sessions);
  **diary/taste** (1-5 enjoyment rating on sessions → avg rating). Hobby-tap
  detail sheet with stats + milestones. 3 tests. (Session timer = the same
  count-up pattern as Creativity; log-with-minutes kept.)
- [x] **Goals** (goals-v2) — DONE: **anti-goals** (say-no list); goal **why**
  (captured on add, resurfaced when the goal stalls < 20%); habit **identity
  framing** ("a vote for <identity>"); habit **streak heatmap** (21-day grid);
  habit **weekday reminders** (`NotificationCategory.habit` + builder, synced
  via `AppContainer.syncHabitReminders` — the Stage-1 notification engine
  paying off). 6 tests.
- [x] **Legal** — DONE: `TermsScreen` + `PrivacyPolicyScreen` (concise,
  honest local-first text) linked from a "Legal" section in `AboutScreen`.

**Done when:** every list CRUD-tested; each screen obeys the anatomy rule.

**✅ STAGE 5 COMPLETE — all 12 spheres have their parity lists + researched
gems. 368 tests green; every migration additive; app builds/installs/launches.**

## Stage 6 — Intelligence (the moat)

*Why here: needs the data breadth from S5 and the AI from S2.*

- [x] **Correlation engine** (§4.1, N2) — DONE: pure `CorrelationEngine`
  (Pearson + 1-day lag, |r|≥0.3 & n≥10, non-causal phrasing) over
  `DailySeries`; `InsightsStore` assembles 9 day-keyed series from the stores
  (mood/stress/energy/meal/sleep/spend/meditation/workouts/hobby); Home
  "Insight of the week" card; `DayKey.shift`/`date(from:)`. 8 tests. **The moat
  feature — no single-sphere app can do this.**
- [x] **N-of-1 experiments** (§11) — DONE: `experiments-v1` migration +
  `Experiment` model (title/note/startDate/durationDays/status, dayNumber/
  daysRemaining/isWindowComplete helpers); pure `ExperimentEngine.analyze`
  compares each `DailySeries` (from `InsightsStore`) during the window against
  the equal-length baseline just before it → `MetricEffect` (baseline vs during
  mean, delta, % change, per-window n), requires ≥3 logged days each side, sorts
  by strongest % change; `headline` verdict. `ExperimentStore` (CRUD + start/
  setStatus/remove + `analysis`/`headline`). `ExperimentsScreen` (list + detail
  "What changed" + AddExperimentSheet 7/14/21/30-day picker); Home active-
  experiment progress card + an "Experiments" entry button. 13 tests. **Turns
  passive logging into personal science — the moat, generalised from Bearable.**
- [x] **Proactive nudges** (§4.2, N3) — DONE: pure `NudgeEngine` (6 rules:
  streak-lapse evening, stress-3-days, budget-90%, sleep-debt, stale-contact,
  thirsty-plant) over a `NudgeContext`; `NudgeScheduler` enforces per-rule
  cooldown + one-nudge-per-day cap; `NudgeStore` assembles context from the
  stores + persists the ledger (`nudges-v1`); Home nudge card (dismiss =
  acknowledge → starts cooldown). 7 tests.
- [x] **Weekly narrative review** (§4.3, N5) + **Life Wheel** (N6) — DONE:
  `reviews-v1` migration + `Review` model (weekly/monthly/lifeWheel, periodKey,
  markdown content, selfRatings JSON); `ReviewStore` builds the trailing-7-day
  digest from mindfulness/health/rest/finance/insights, persists reviews, and
  streams the narrative via `AgentService.weeklyNarrative` (warm reflection +
  one open question, saved as an Engram note). Pure `LifeWheel.deltas`/`insight`
  compares 12 self-ratings (1–10) against the computed Life Score — the gap is
  the insight. `WeeklyReviewSheet` (digest + streamed reflection + user note)
  and `LifeWheelSheet` (12 sliders → grouped Swift Charts bar of feeling-vs-data
  + delta list). Home `reviewsSection` with two entry buttons; the weekly one is
  highlighted on Sunday evenings. 12 tests.
- [x] **Adaptive "Today" verdict / energy schedule** (§11) — DONE: pure
  `ReadinessEngine` — `rawScore` (sleep vs goal → 60, low stress → 40, unknown
  → neutral 20, mirrors Rest's proven formula), `correction` (mean gap between
  felt energy 1–5→20–100 and past predictions, ≥3 overlapping days, clamped
  ±15), `verdict` → score/band(low/mod/high)/headline/recommendation +
  `focusWindow` (~wake+2h, shorter+later when low) + `windDown` (bedtime−30m).
  `readiness-v1` migration (`readiness_log` dateKey→predicted); `ReadinessStore`
  builds input from Rest/Mindfulness/Health, records the daily raw prediction,
  and `rateEnergy` closes the self-correction loop. Home hero `todayVerdictCard`
  (score + line + Focus/Wind-down chips + a one-tap "How does today feel?"
  RatingSelector). 13 tests. **Self-correcting was RISE's #1 failure — we fix
  it by learning from felt-energy.**
- [x] **Agent features** (§4.4) — DONE: one streaming primitive
  `AgentService.assist(AgentTask)` (per-case system/prompt/Engram-recall/observe)
  + one reusable `AgentResultSheet` (SphereUI) that streams any task, regenerates,
  and degrades gracefully with no backend. Wired four entry points: pre-meeting
  **briefing** (Relationships contact sheet, recalls by name + prep facts), goal
  **decomposition** ("Break this down" on a GoalCard → milestones + first steps),
  **interview prep** (Career → paste role + JD → tailored questions), and
  cross-sphere **pattern analysis** ("Analyze my patterns" on Home, feeds weekly
  correlations + digest). Brag document already shipped (S5). 4 tests. Deferred:
  decomposition confirmation-chips that create tasks via tools; per-sphere footer
  pattern-analysis on all 12 screens (Home covers the cross-sphere case); mock-
  interview follow-up in chat.

**Done when:** correlation engine unit-proven; ≤1 proactive nudge/day
enforced.

## Stage 7 — Platform integrations

*Why here: entitlement-heavy; leans on the App Group (S1); independent of
the intelligence stage.*

- [x] **HealthKit write-back** (§6, C4) + **sleep auto-import** (kills manual
  sleep logging) + cycle read. — DONE: (a) sleep — pure `SleepImport.nights`
  (per-night hours by wake-day, awake ignored) + `recentSleepNights`, RestStore
  import fills only un-logged nights (idempotent), RestScreen import row + auto.
  (b) write-back (C4) — `writeWeight`/`writeWaterGlass`/`writeWorkout` on the
  provider (default no-ops; `HealthKitService` saves bodyMass/dietaryWater +
  `HKWorkoutBuilder`), HealthStore mirrors weight/water/workout logs to Health.
  (c) cycle read — pure `CycleImport.periods` (groups consecutive flow days into
  periods, heaviest wins) + `recentCycleFlow` (menstrualFlow), `importCycle
  FromHealth` skips already-logged starts, auto on Health appear when `showsCycle`.
  Auth now requests share types; usage strings updated. 23 tests. **Actual sync
  needs a real device — the simulator has no HealthKit data.**
- [x] **Contacts import** (§6) — DONE: `ContactsProviding` protocol +
  `ImportedContact` (SphereCore, Contacts-framework-free); pure `ContactImport`
  (`newContacts` dedupes vs existing names case-insensitively + within the batch,
  `makeContact` maps to a sphere `Contact` with birthday). `RelationshipsStore`
  gained `contactsProvider` + `importableContacts()` (requests access, filters)
  + `importContacts(_:)`. App-target `ContactsService` (CNContactStore, read-only,
  name + birthday). RelationshipsScreen toolbar Menu → "Import from Contacts" →
  `ContactPickerSheet` (multi-select, pre-selected, birthday hint). 8 tests +
  `NSContactsUsageDescription`. **Verify the picker/permission on device.**
- [x] **EventKit calendar context** (§6, C8) — DONE: `CalendarProviding`
  protocol + `CalendarEvent` (SphereCore, EventKit-free); pure `CalendarContext`
  (`today` filters/sorts all-day-first, `timeLabel`, `summary` one-line agenda
  for the brief). `HomeStore` gained `calendarProvider` + `todayEvents` +
  `refreshCalendar()`; `streamBrief` folds the agenda in automatically. App-target
  `EventKitService` (full-access, read-only). Home "Today's schedule" card +
  refresh in `.task`. 11 tests + `NSCalendarsFullAccessUsageDescription`.
- [x] **Global search** (§6, C5) — DONE: pure `GlobalSearch` ranker over
  `SearchItem`s (AND semantics — every token must match; title/prefix matches
  outrank body; grouped by sphere in best-hit order) + `SearchStore` that
  assembles a live corpus from 11 spheres' title-bearing records and surfaces
  matching Engram memories via `crossAgentRecall`. `GlobalSearchScreen`
  (`.searchable`, sections per sphere with rows navigating to the sphere +
  a Memories section); magnifying-glass entry in the Home toolbar. 8 tests.
- [x] **MapKit visited-countries map** (Travel) — DONE: pure `VisitedMap`
  (`distinctCountryNames` dedupe/sort + `region(fitting:)` bounding-box → center
  + padded span, clamped to the globe) with a CoreLocation-free `GeoCoordinate`;
  `VisitedMapScreen` (SphereUI) geocodes country names via `CLGeocoder`, drops a
  `Marker` per country, fits the camera, shows a "N of M mapped" banner; "Map"
  link in the Travel visited section. 5 tests. **Geocoding needs a device/network.**
- [x] **watch extras** (shopping list, voice agent query) — DONE: `WatchCommand`
  gained `.checkShopping(id)` + `.askAgent(query)`; `WidgetSnapshot` gained
  `shopping: [ShoppingLine]` + `agentReply` (tolerant decoder for older payloads);
  `AgentService.answer` one-shot; phone `apply` toggles the shopping item /
  answers the query and pushes the result back on the next snapshot; watch UI got
  a tap-to-check Shopping list + a `TextFieldLink` "Ask" (dictation) showing the
  reply. Command up, result down — reuses the existing WCSession snapshot channel.
  4 tests. **Round-trip needs a paired watch.**
- [x] **trip photo memories** — DONE: `travel-v3` migration (`trip_photos`) +
  `TripPhoto` model + `TripPhotoStoring` protocol (SphereCore, UIKit-free);
  `TravelStore` gained `photoStore` + `tripPhotos` + `photos(for:)`/`addPhoto`/
  `removePhoto`/`photoURL`. App-target `TripPhotoStorage` (downscales to 1600px
  JPEG in the App Group). TripDetailView "Photo memories" section — `PhotosPicker`
  to add + a horizontal thumbnail strip (`TripPhotoThumb` lazy-loads cross-platform)
  with delete. 6 tests.

**Done when:** sleep import replaces manual logging; contacts import
round-trips. ✅ **Stage 7 complete.**

## Stage 8 — Downloadable models (AI Tier 1)

*Why late: the most complex AI piece; Tier 0 already delivers free AI, so
this adds choice + reach for non-Apple-Intelligence devices.*

- [x] **Model manager** (§9.3) — DONE: `ModelCatalog` (5 curated models with
  size/RAM/context metadata) + pure `ModelFit` (RAM-fit tiers + disk margin +
  size labels) + `ModelManager` (@Observable: per-model download state, install/
  active tracking, cancel) over `ModelDownloading` + `ModelPreferenceStoring`
  protocols. App-target `ModelDownloadService` (real URLSession download to
  Application Support excluded-from-backup, Wi-Fi-preferred, disk/RAM introspection,
  `.complete` marker) + `ModelPreferences`. SphereUI `ModelsScreen` (size + RAM-fit
  badges, Get/Cancel/Delete, progress, pick-active) linked from Settings → AI.
  10 tests. **Actual multi-GB download + inference land with LocalModelEngine.**
- [x] **LocalModelEngine** (§9.1 Tier 1) — DONE (text-only v1): `AIBackend`
  gained `.localModel`; `AgentService` gained an injected `localModelEngine`
  closure — resolution: explicit choice → Apple on-device → downloaded model →
  cloud keys. App target: `mlx-swift-examples` package (app ONLY, never
  extensions), `LocalModelEngine` (MLX `ChatSession` streaming/respond, model
  container cached via actor, engine cached per hubID), `MLXModelService`
  (real Hub download with progress, replaces the URLSession placeholder on
  device; sim keeps the fallback), `LocalModelAI` gate — engines only off the
  simulator. Settings picker gained "Downloaded model" when one is installed.
  `ModelInfo.hubID`. Device build compiles the MLX path; sim runs the UI. CI
  gained a Metal-toolchain step (Xcode 26 ships it separately). 7 tests.
  **Runtime inference needs a real device (MLX = device GPU); constrained
  decoding for tool calls is a follow-up.**

**Done when:** a non-Apple-Intelligence device can download a model and chat.

## Stage 9 — Polish & virality

- [x] **SphereUI (uk) localization** (C9) — DONE (static strings): mechanism —
  SphereUI `Text` literals resolve against `Bundle.main`, so the app's
  `Localizable.xcstrings` drives them (no per-`Text` `bundle:.module`, no package
  changes). Harvested every static SphereUI label (Text/Label/Section/nav-title/
  Button/Toggle/Picker/TextField/prompt) — **428 candidates, all 428 now have uk**;
  catalog grew 53 → 469 keys, all compiled into `uk.lproj` and confirmed rendering
  in Ukrainian. Interpolated word-bearing strings ("Day %lld of %lld", "%lld of
  %lld selected", "%lld min this week"…) added too as format-keys mirroring
  SwiftUI's `LocalizedStringKey` emission (%lld/%@) — 36 more, catalog 505 keys.
  Pure value/emoji concatenations need no translation; a few date-style /
  trailing-`%` keys left English (uncertain format, harmless fallback).
- [x] **"Year in Sphere" recap** (§11) — DONE: pure `YearInSphere` (`RecapStats`
  → `RecapCard`s, skips zero metrics, intro card, `summaryLine` for sharing,
  thousands formatting) + `RecapStore` (aggregates the year across mindfulness/
  health/learning/travel/goals/creativity/hobbies by calendar year). `YearInSphere
  Screen` — paged TabView of colourful per-sphere gradient cards + a share card
  with `ShareLink`. Entry: "Your Year in Sphere" row in Profile. Free + shareable
  by design. 8 tests, strings localized.
- [x] **Momentum-over-percentage** framing (§11) — DONE: pure `Momentum`
  (`MomentumBand` dormant→thriving + emoji; `forStreak`/`forProgress` bands;
  `streakPhrase` "On a roll · 9 days" / `progressPhrase` "Building momentum",
  reframing the bare %). GoalCard leads with the warm phrase + emoji (% demoted
  to a secondary digit); HabitRow shows a momentum line under the heatmap. 5
  tests, strings localized. Spotlight donation + remaining P3s deferred.
- [x] **Final code review** — DONE: 3 parallel reviewers over all Stage 6-9 code.
  Fixed: ModelManager cancel-restart task-clobber race (generation tokens gate
  state writes + map cleanup); RecapStore counted lifetime books/goals into every
  year (no completion dates → metrics removed from the per-year recap);
  InsightsStore "Meditation" series included `.focus` sessions (now filtered,
  matching `hasMeditated`); cycle import deduped only by exact start day (now
  range-overlap vs existing entries); `Experiment.isWindowComplete` off-by-one
  (now true on the final day, consistent with `daysRemaining == 0`);
  `YearInSphere.formatted` broke ≥1M (general digit grouping); EventKit fallback
  id could collide (endDate added); ModelDownloadService doc no longer claims
  resumable/progress it doesn't have. Cleared as sound: WidgetSnapshot tolerant
  decoder, sleep-import dedup, `@unchecked Sendable` services, stream
  cancellation, no force-unwraps. 502 tests green.

---

## Post-launch (unchanged, do not start ad hoc)

- Phase 8 — CloudKit sync (CKSyncEngine).
- Phase 9 — Engram v2 (on-device reflection, hybrid recall).

## Working rules (from HANDOFF)

- After adding a new `.swift` to the app target: `xcodegen generate` before
  building; confirm `** BUILD SUCCEEDED **` (never trust a bare
  `simctl launch`).
- `swift test` green after every SphereCore change; every pure engine gets
  exhaustive tests.
- Screenshots: the user captures final framed shots — I list the screens.
- Don't drive computer-use to screenshot the simulator (blocks the user's
  machine).
