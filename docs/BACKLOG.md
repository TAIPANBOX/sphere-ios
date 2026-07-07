# Product backlog — per-sphere gap analysis and ideas

Snapshot date: 2026-07-04. Sources: full inventory of the Flutter reference
(`../sphere`) vs the current iOS port. Two kinds of items per sphere:
**Parity** (existed in Flutter, not yet ported) and **New** (beyond the
Flutter app, native-platform or UX wins).

Priorities: **P1** = worth doing before launch, **P2** = first post-launch
updates, **P3** = later / opportunistic.

---

## Cross-cutting (highest leverage)

| # | Item | Why | Pri |
|---|------|-----|-----|
| C1 | ~~**Notifications engine** — one opt-in center: water reminders, medication times, bedtime wind-down, plant watering, subscription renewals, morning brief.~~ DONE (2026-07-06): pure `NotificationPlanBuilder` builders per category, `AppContainer.syncReminders()` orchestrates every category from live store data in one idempotent sync, Settings exposes a per-category opt-in. Both remaining clauses shipped 2026-07-07: proactive-nudge notifications (`NotificationPlanBuilder.nudge` schedules one non-repeating 11:00 reminder for `NudgeStore.activeNudge` when the toggle is on, today-or-tomorrow depending on whether 11:00 has passed, id keyed on the nudge id for idempotent re-syncs) and wellbeing-pause suppression (`NotificationCategory.isCriticalDuringWellbeingPause` — medication + birthday only; `syncReminders()` builds plans for just those two categories while `profile.isWellbeingPaused()`, and `setWellbeing` now re-syncs so pausing/resuming takes effect immediately). | Retention driver; the data is already in the stores | P1 |
| C2 | ~~**Interactive widgets (App Intents, iOS 17)** — log water / mark meditation done directly from the home-screen widget without opening the app.~~ DONE (2026-07-06): `QuickLogIntents.swift` shared verbatim into the `SphereWidgetExtension` target (project.yml source entry) so `Button(intent:)` compiles there; the intents patch the persisted `WidgetSnapshot` (waterToday / meditatedToday) right after writing so a tap reflects instantly, then reload timelines. Water + meditation buttons on systemSmall (water only)/systemMedium/systemLarge (widget now supports `.systemLarge` too). Mood skipped (needs a value picker). App reload-on-foreground added (`SphereApp.swift` `.active` case) so a widget/Siri write isn't clobbered by stale in-memory stores. | Native killer feature; widget infra already exists | P1 |
| C3 | ~~**Siri / Shortcuts via App Intents** — "log a glass of water", "log mood 4", "how's my day".~~ DONE (shipped earlier): `Sphere/Sources/QuickLogIntents.swift` — `LogWaterIntent`, `LogMoodIntent`, `LogMeditationIntent` + `SphereShortcuts` (`AppShortcutsProvider`) registering Siri phrases, confirmed already in place before this pass. | Same intents as C2, one implementation | P1 |
| C4 | ~~**HealthKit write-back** — workouts, mindful minutes, weight, water written TO HealthKit, not just read.~~ DONE (2026-07-06): workouts/weight/water already wrote via `HealthKitService` (`HKWorkoutBuilder`, `HKQuantitySample`); this pass added mindful minutes — `MindfulSessionWriting` protocol (`writeMindfulSession(start:end:)`), `HealthKitService` conforms and saves an `HKCategorySample` of type `.mindfulSession` (value `.notApplicable`), added to the share/write authorization set. `MindfulnessStore` takes an injected `mindfulWriter` and fires the write-back from `add(_ session:)` (covers meditation, breathing, and focus sessions — all route through `add`), skipping zero/negative durations; failures are silently swallowed (fire-and-forget), matching `HealthStore`. Not covered: the widget/Siri `LogMeditationIntent` path writes straight to the shared DB from the extension process and does not mirror to HealthKit (extension-process auth complexity) — the store path is the intended deliverable. | Two-way trust; users expect Apple Health to be source of truth | P1 |
| C5 | **Global search** — one search field over goals/tasks/contacts/books/journal; Engram FTS5 + per-store filters already give 80% | Data is scattered across 12 spheres; finding beats browsing | P2 |
| C6 | ~~**Face ID / passcode app lock** — health, finance, journal are sensitive.~~ DONE (2026-07-06): `LockGate` wraps the whole app, biometrics with passcode fallback, re-auth after background; opt-in in Settings, mirrored to `UserProfile.appLockEnabled` for export. Hardened this pass: an opaque privacy cover on any non-active scene phase (so the app-switcher snapshot can't leak data), and fail-open when the device has neither biometrics nor a passcode (never traps the user out). | Table stakes for a life-data app | P1 |
| C7 | ~~**Data export/backup (JSON/CSV)** — pre-CloudKit safety hatch~~ DONE (verified done 2026-07-07, shipped earlier): Settings has "Export all data" (`SettingsScreen.swift` `runExport`) calling `DataExporter.exportJSON(from:)`, which reads every GRDB table and serializes to versioned JSON. | No sync until Phase 8; users need an exit | P1 |
| C8 | **EventKit calendar context** in the Meta Agent brief (Flutter had it) + profile context (HANDOFF note) | Brief quality; parity | P2 |
| C9 | ~~**SphereUI localization (uk)**~~ dropped by product decision 2026-07-07 — English-only market; localization effort reverted (recoverable from git history). | Mechanical, big volume | P1 |
| C10 | ~~**Watch voice agent query** — dictate from the wrist, phone runs AgentService, reply back~~ DONE (verified done 2026-07-07, shipped earlier): `WatchCommand.capture(text:)` sent from the watch (`WatchConnectivityStore`/`WatchSession`) reaches `AppContainer.apply` on the phone, which calls `agent.captureOrAnswer(text:tools:)` and pushes the reply back via `WidgetSnapshot.agentReply`. | Planned watch increment | P2 |
| C11 | ~~**Empty-state coaching** — every sphere screen gets a friendly zero-data state with one-tap seed actions ("Add your first…")~~ DONE (2026-07-06): shared `EmptyStateCard` (`SphereUI/Components/`) — sphere emoji, title, one warm guidance line, accent-tinted "Add your first…" button, gentle-motion fade/scale-in. Wired at the top of all 12 screens, each with its own emptiness condition (whole-screen, not per-section) and its existing add-flow sheet: Goals (goals+habits empty → Add Goal), Health (no weight + no workouts → Log Weight), Finance (no transactions+accounts+subscriptions → Add Transaction), Learning (no books+skills → Add Book), Career (no tasks+network → Add Task), Relationships (no contacts → Add Contact), Rest (no sleep entries → Log Sleep), Hobbies (no hobbies → Add Hobby), Travel (no plans+wishlist → Add Trip), Mindfulness (no sessions+journal → Log Meditation), Creativity (no projects+ideas → Add Project), Home (no tasks+plants+shopping → Add Task). | First-run experience across 12 screens | P1 |
| C12 | **Haptics + undo** — haptic on quick logs; snackbar undo for destructive swipes | Perceived quality | P2 |
| C13 | ~~**Notification actions** — complete reminders from the wrist / lock screen without opening the app~~ DONE (2026-07-07): `NotificationPlan` gained an optional `actionCategoryIdentifier` + Sendable `[String:String]` `userInfo`; builders thread the medication/plant/habit id through and tag water reminders (see `NotificationAction` constants in SphereCore). App: `NotificationEngine.registerCategories()` registers the `UNNotificationCategory` set (water → "Log a glass" + "Snooze 30 min"; medication → "Mark taken"; plant → "Mark watered"; habit → "Done") and stamps category/userInfo onto each request; `NotificationActionHandler` (`UNUserNotificationCenterDelegate`, wired in `AppContainer.init`) routes action taps — from the iPhone lock screen or a mirrored watch notification, both delivered to the phone — into `AppContainer.applyNotificationAction`, which reloads the store, writes idempotently (new `HealthStore.markMedicationTaken`, `GoalsStore.checkInHabit`; plant reuses `water(id:)`), resyncs reminders, and refreshes the widget. Snooze schedules a one-off +30min water reminder. | Highest-value wrist interactivity; reminders already exist | P1 |
| C14 | ~~**Double Tap** — log water on the watch without touching the screen~~ DONE (2026-07-07): `.handGestureShortcut(.primaryAction)` on the watch water quick-log button (`Watch/SphereWatchApp.swift`). watchOS 11 API, matches the deployment target so no availability guard; fires on Double Tap-capable watches (Series 9 / Ultra 2+). | One line, real Ultra polish | P2 |
| C15 | ~~**Watch Smart Stack interactive widget** — log water from the Smart Stack without opening the app~~ DONE (2026-07-07), shipped INTERACTIVE (not the deep-link fallback). Investigation: `Button(intent:)` is available on watchOS 10+ (the `_AppIntents_SwiftUI` overlay ships a `SwiftUI.Button` intent initializer for watchOS — verified in the SDK) and accessory widgets render it, so Option 1 in the Watch-L2 brief is viable. The watch widget extension has no WCSession/DB, so `LogWaterWatchIntent` (shared into the extension + the watch app) queues `.logWater` into the shared App Group via new `PendingWatchLogStore` (bounded to 50, `drain()` clears → idempotent) and optimistically patches the persisted `WidgetSnapshot` (`incrementingWater(by:)`) for instant feedback; the watch app drains the queue on activation and on WCSession reachability, relaying real `WatchCommand`s to the phone (unsent → re-queued). New `.accessoryRectangular` "Log Water" widget in `SphereWatchWidget.swift`. | Native wrist logging; widget infra existed | P2 |
| C16 | ~~**Watch App Shortcuts / Action Button** — "Log water" from Siri on the wrist and assignable to the Ultra Action Button~~ DONE (2026-07-07): `WatchShortcuts` (`AppShortcutsProvider`, watch app target only, `Watch/WatchShortcuts.swift`) exposes "Log water" via `LogWaterWatchIntent`, reusing the C15 queue-and-drain path (intent runs in the watch app process, queues + patches, `WatchModel` relays on next reachability; drain-on-launch covers the Action-Button-launches-the-app case). `AppShortcutsProvider` is watchOS 9+. Nothing descoped. | Ultra Action Button parity | P2 |

## Home tab

- Parity: quick-action buttons row (jump to a sphere log), model selector on the brief card, regenerate button, location/calendar toggles. **P2**
- New: pull-to-refresh brief; brief renders offline from cache with "as of" stamp (cache exists); Today's Focus swipe-to-complete inline. **P2**
- New: "streaks strip" on Home (meditation, detox, reading) for motivation. **P3**

## Health

- The Health screen's first-run "Connect Apple Health" card was removed
  (2026-07-07) — it could render invisible on screen re-entry and the root
  cause stayed elusive across two fix attempts. Device-data onboarding now
  lives in Settings → Import from device, one screen for Apple Health,
  Contacts, and Calendar & Reminders.
- Device import now covers workouts and weight history too (2026-07-07):
  `HealthKitService.recentWorkouts(days:)` / `weightHistory(days:)` read up to
  a year back, excluding samples the app itself wrote to HealthKit (source
  predicate) so re-import never duplicates our own write-back. `HealthStore
  .importWorkoutsFromHealth` / `importWeightsFromHealth` dedup against
  manually-logged entries (workout: same day + type + duration within a
  minute; weight: same day already logged) and persist via the existing
  add/save paths. The Calendar row also imports open Reminders into Career
  tasks (`ReminderImport`, EventKit's separate `requestFullAccessToReminders`
  permission) — same "no new rows" screen, more data per row.
- Parity: doctors list, menstrual-cycle tracker (female profile), daily stress entry lived here too, conditions list surfaced (profile has it). **P2**
- New: medication reminders at dose times (uses C1); weight trend chart with goal line; water goal adaptive to weather/workouts; lab-result out-of-range highlighting already done — add history per marker. **P1–P2**
- New: HealthKit background delivery so steps/sleep update without opening the app. **P2**

## Finance

- Parity: debts/loans, investments. **P2**
- New: ~~monthly category breakdown chart (donut/bars) — biggest missing visual~~ DONE (verified done 2026-07-07, shipped earlier): `FinanceScreen.categoryChartCard` renders a `Charts`/`BarMark` breakdown over `store.categorySpendingThisMonth()`. Remaining in this line: upcoming renewals feed Today's Focus; recurring-transaction detection ("this looks monthly — make it a subscription?"); budget month rollover option; CSV import. **P1** for the chart, rest **P2–P3**
- New: net-worth trend line from account balances. **P3**

## Learning

- Parity: courses, languages, flashcards, weekly study chart, **Pomodoro timer**. **P2**
- New: Pomodoro as **Live Activity + Dynamic Island** — flagship native win. **P2**
- New: flashcards with **spaced repetition reusing Engram's Ebbinghaus math** (same decay curve, inverse use). Elegant, code exists. **P2**
- New: reading pace ("14 pages/day finishes by Aug 3"), yearly books goal, quote sharing as image. **P3**
- New: book metadata autofill by title (OpenLibrary, optional network). **P3**

## Career

- Parity: skills inventory, salary history, career goals, market insights. **P2** (salary+skills), **P3** (insights)
- New: interview prep flow — agent generates likely questions from a pasted job description, then mock-interviews in chat. **P2**
- New: stale network contacts → Today's Focus ("ping Iryna, 74 days"); achievements → export brag-sheet (markdown) for reviews/CV. **P2–P3**

## Goals

- Parity: weekly/monthly review buttons (guided agent reflection), upcoming calendar events, pattern analysis. **P2**
- New: habit streak heatmap (calendar grid); habit reminders per weekday; goal check-in nudge if progress unchanged 14+ days; link a goal to concrete tasks in other spheres (career/home) and roll progress up. **P2**, linking **P3**

## Mindfulness

- Parity: ~~daily affirmation card~~ DONE (verified done 2026-07-07, shipped earlier): `MindfulnessStore.customAffirmations`/`dailyAffirmation(for:)` (stable per-day pick) plus `addAffirmation`/`removeAffirmation`; streak calendar heatmap, body-scan guide, session notes still open. **P1** (affirmations are cheap + loved), heatmap **P2**
- New: more breathing patterns (box 4-4-4-4, coherent 5-5) with haptic-guided pacing (no need to look at screen); ~~write mindful minutes to HealthKit (C4)~~ DONE (2026-07-06); journal prompts from the agent based on recent mood; mood↔sleep correlation insight (cross-sphere, data exists). **P2**

## Rest

- Parity: relaxation section (music/podcast links), detox schedule (not just day toggle). **P3**
- New: ~~**HealthKit sleep auto-import** — kills manual sleep logging, the single biggest UX upgrade in the sphere.~~ DONE (verified done 2026-07-07, shipped earlier): `RestScreen.healthImportRow` auto-triggers `RestStore.importSleepFromHealth(days:)` on appear (manual fallback button still present); `HealthKitService` queries real `HKCategoryType(.sleepAnalysis)` samples. **P1**
- New: bedtime wind-down notification from schedule (C1); sleep debt number (target vs 7-day actual); burnout warning surfaced in Today's Focus when work-hours trend high. **P2**

## Travel

- Parity: itinerary notes per trip (we have notes; Flutter grouped past trips timeline). **P3**
- New: MapKit map of visited countries (shaded) — high-delight, low-risk; passport/visa expiry reminders (uses C1); destination weather in trip card near departure; packing template library by trip type (we have per-type checklists — promote to editable templates). **P2**
- New: trip countdown widget option. **P3**

## Home sphere

- Parity: appliances (warranty/purchase), utilities meters/bills, renovation projects, home inventory. **P2** (appliances+utilities), **P3** (renovation, inventory)
- New: ~~recurring chores (weekly cleaning auto-respawn) — biggest practical gap~~ DONE (verified done 2026-07-07, shipped earlier): `HomeSphereStore.toggle(id:)` calls `RecurringChore.nextOccurrence(after:)` and inserts the next occurrence on completion; plant watering notification (C1); shopping list on the Watch (check off in the store!) still open. **P1** (recurring chores), **P2** (watch list)

## Creativity

- Parity: portfolio gallery, project work sessions (time tracking + weekly chart). **P2**
- New: session timer with per-project totals (feeds Life Score genuinely); idea→project one-tap promotion; attach photos to inspiration items. **P2–P3**

## Hobbies

- Parity: fully ported (charts slightly richer in Flutter). 
- New: session timer (start/stop, not just manual minutes); "behind weekly target" nudge into Today's Focus; equipment wishlist with prices linked to Finance savings goal. **P2–P3**

## Relationships

- Parity: contact detail editing sheet polish. **P2**
- New: ~~**import from iOS Contacts** (names + birthdays) — removes the cold-start wall, biggest win in the sphere.~~ DONE (verified done 2026-07-07, shipped earlier): `ContactsService`/`CNContactStore` wraps device Contacts, `ContactsImport.newContacts` in SphereCore, wired via `RelationshipsStore.importableContacts()`/`importContacts(_:)` and the Relationships screen's "Import from Contacts" menu action. **P1**
- New: check-in quick action (prefilled iMessage draft via `sms:`); anniversaries/custom dates, not just birthdays; gift idea → Home shopping list link. **P2–P3**

---

## Beyond parity — novel ideas (in neither Flutter nor iOS)

Grounded in retention research: ~92% of habit-tracking attempts die within
60 days, mostly from logging fatigue, rigidity, and guilt mechanics; streak
"forgiveness" (Duolingo's freeze) cut churn ~21%. The differentiator Sphere
uniquely owns: 12 spheres of day-keyed data + on-device Engram + agents —
no single-sphere app can correlate across life domains.

### Cross-cutting (the identity features)

| # | Idea | Notes | Pri |
|---|------|-------|-----|
| N1 | ~~**Universal quick capture** — one "+" field (and Share/Action extension): type or dictate "coffee 4.50, mood 4, ran 5k"; the local agent routes it through existing sphere tools~~ DONE (verified done 2026-07-07, shipped earlier): `QuickCapture.run`/`CaptureRuleParser.parse` route free text through `SphereToolRegistry`; reachable from Home via the "Tell your agent anything" sheet (`HomeScreen.swift` → `QuickCaptureSheet`). | Kills logging fatigue, reuses SphereToolRegistry as-is | P1 |
| N2 | ~~**Cross-sphere correlation insights** — weekly on-device stats over day-keyed data: "mood averages +1.2 on workout days", "spending spikes on poor-sleep days"~~ DONE (verified done 2026-07-07, shipped earlier): `CorrelationEngine` + `InsightsStore` (`Insights/`) built in `AppContainer` and surfaced on Home via `insights.weeklyInsights(limit:)`. | Impossible for single-sphere apps; data already exists | P1 |
| N3 | **Proactive agent** — pattern-triggered check-ins (stress up 3 days + no meditation → gentle suggestion), budget cap approaching, streak about to lapse | The "companion" promise made real; needs notification engine | P2 |
| N4 | ~~**Forgiveness mechanics everywhere** — sick mode / vacation mode pauses ALL streaks and softens Life Score; streak freeze tokens~~ DONE (verified done 2026-07-07, shipped earlier): `UserProfile.WellbeingMode` + `isWellbeingPaused(asOf:)`, `AppContainer.applyWellbeing(asOf:)`, and `StreakPolicy` (excused-day streak bridging, including mindfulness excused days). | Research-backed churn killer; humane by design | P1 |
| N5 | **Weekly narrative review** — agent writes the story of your week across spheres + one reflective question; saved as a journal artifact | Insight > raw data; retention ritual | P2 |
| N6 | **Life Wheel audit (quarterly)** — user self-rates all 12 spheres 1–10; delta vs computed Life Score is the insight ("you feel worse about Finance than your data says") | Classic coaching tool, perfect fit for the 12-sphere model | P2 |
| N7 | ~~**Privacy as a feature** — local-first + Face ID + explicit "your data never leaves the device except your own LLM key" screen~~ DONE (verified done 2026-07-07, shipped earlier): `PrivacyScreen` (in `LockGate.swift`) with Face ID/Touch ID via `LAContext` and explicit local-first copy. | Users now ask for E2E/privacy explicitly; we already are this — say it | P1 |

### Per sphere

- **Health**: symptom quick-log with agent correlation vs sleep/stress/cycle;
  "sick mode" (ties N4); meal-quality 1–5 tap (deliberately NOT calorie
  counting — anti-fatigue); daily energy level (1–5) as the cheapest
  correlant for N2.
- **Finance**: **"safe to spend today"** number (month budget − committed −
  spent, divided by days left); impulse wishlist with 72h cooling-off before
  it becomes a purchase; subscription price-increase detection (amount
  changed vs last cycle); financial runway ("4.2 months of expenses in
  savings").
- **Learning**: daily resurfacing of YOUR OWN quotes/notes via the Engram
  Ebbinghaus curve (Readwise-style, zero new infra); honest **skill decay**
  (unpracticed skills fade on the 1–5 scale); unified "learning queue"
  (articles/videos/courses to consume) via Share extension.
- **Career**: auto **brag document** — done tasks + achievements roll into a
  quarterly review-ready markdown; 1:1 meeting notes per manager/report with
  agent-prepared talking points; workday energy log vs meeting load.
- **Goals**: agent **goal decomposition** (big goal → milestones → concrete
  actions placed into the right spheres); capture the "why" at creation and
  resurface it when progress stalls; anti-goals (things to say no to).
- **Mindfulness**: **gratitude practice** (3 things, evening prompt) — the
  single most-validated wellbeing intervention, absent in both versions;
  voice journaling (dictation infra exists, transcript + audio note);
  evening reflection generated from the day's actual data ("you closed 3
  tasks and walked 12k — what felt best?").
- **Rest**: **vacation balance tracker** (days off used/left per year);
  recovery-activities menu with personal effectiveness ratings (learn what
  actually restores YOU — feeds N2); nap logging; social-battery level.
- **Travel**: trip budget linked to Finance (planned vs actual per trip);
  trip journal/photo memories per trip (auto-collect photos taken in date
  range); jet-lag shift plan (bedtime nudges 3 days before flight); offline
  country card (emergency numbers, embassy, plug type).
- **Home**: seasonal maintenance checklists (winterize/spring); meter
  readings history with anomaly flag; warranty vault (receipt photo +
  expiry reminder); maintenance cost rollup → Finance.
- **Creativity**: WIP photo timeline per project (progress gallery);
  daily creative prompt by discipline; **momentum indicator** (gentle
  "cooling down" instead of guilt streaks — ties N4).
- **Hobbies**: cost-per-session stat (equipment + spend ÷ sessions — joy
  per hryvnia); progression milestones per hobby (beginner→advanced
  checklist); "try something new" suggestions from existing interests.
- **Relationships**: **pre-meeting briefing** — agent surfaces stored facts
  before a check-in ("Ostap's daughter started school in September; last
  talked 74 days ago about his startup"); interaction quality (deep/casual)
  not just frequency; loneliness guard — declining-contact trend triggers a
  gentle nudge (ties N3).

### Novel top 5 (my pick)

1. N1 universal quick capture — attacks the #1 abandonment cause directly
2. N2 correlations + Health energy log — the moat feature, on-device
3. N4 sick/vacation mode — cheap, humane, research-backed retention
4. Finance "safe to spend today" — single most-loved number in budget apps
5. Mindfulness gratitude + Relationships pre-meeting briefing — daily/weekly
   delight moments that showcase Engram

---

## Suggested order (top 10)

1. ~~C6 Face ID lock + C7 data export (trust foundation, small)~~ DONE (verified done 2026-07-07, shipped earlier)
2. C1 notifications engine (water/meds/bedtime/plants/renewals/brief)
3. C2+C3 App Intents: interactive widget + Siri quick logs
4. ~~Rest: HealthKit sleep auto-import~~ DONE (verified done 2026-07-07, shipped earlier)
5. ~~Relationships: iOS Contacts import~~ DONE (verified done 2026-07-07, shipped earlier)
6. ~~Finance: monthly category chart; Home sphere: recurring chores~~ DONE (verified done 2026-07-07, shipped earlier)
7. ~~C11 empty states~~ DONE (2026-07-06) + Mindfulness affirmations (cheap delight, affirmations already shipped)
8. ~~C9 SphereUI uk localization~~ dropped (2026-07-07): English-only market
9. ~~C4 HealthKit write-back~~ DONE (2026-07-06)
10. Learning: Pomodoro + Live Activity (post-launch headline feature)

Phases 8 (CloudKit) and 9 (Engram v2) remain post-launch as planned; C7
export is the interim answer to data safety.
