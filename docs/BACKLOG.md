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
| C1 | ~~**Notifications engine** — one opt-in center: water reminders, medication times, bedtime wind-down, plant watering, subscription renewals, morning brief.~~ DONE (2026-07-06): pure `NotificationPlanBuilder` builders per category, `AppContainer.syncReminders()` orchestrates every category from live store data in one idempotent sync, Settings exposes a per-category opt-in. Not yet: proactive-nudge notifications (`.nudge` category defined but unscheduled — nudges stay an in-app surface), and wellbeing-pause suppression of non-critical reminders. | Retention driver; the data is already in the stores | P1 |
| C2 | **Interactive widgets (App Intents, iOS 17)** — log water / mark meditation done directly from the home-screen widget without opening the app | Native killer feature; widget infra already exists | P1 |
| C3 | **Siri / Shortcuts via App Intents** — "log a glass of water", "log mood 4", "how's my day" | Same intents as C2, one implementation | P1 |
| C4 | **HealthKit write-back** — workouts, mindful minutes, weight, water written TO HealthKit, not just read | Two-way trust; users expect Apple Health to be source of truth | P1 |
| C5 | **Global search** — one search field over goals/tasks/contacts/books/journal; Engram FTS5 + per-store filters already give 80% | Data is scattered across 12 spheres; finding beats browsing | P2 |
| C6 | **Face ID / passcode app lock** — health, finance, journal are sensitive | Table stakes for a life-data app | P1 |
| C7 | **Data export/backup (JSON/CSV)** — pre-CloudKit safety hatch | No sync until Phase 8; users need an exit | P1 |
| C8 | **EventKit calendar context** in the Meta Agent brief (Flutter had it) + profile context (HANDOFF note) | Brief quality; parity | P2 |
| C9 | **SphereUI localization (uk)** — known debt, strings in `app_uk.arb` | Mechanical, big volume | P1 |
| C10 | **Watch voice agent query** — dictate from the wrist, phone runs AgentService, reply back | Planned watch increment | P2 |
| C11 | **Empty-state coaching** — every sphere screen gets a friendly zero-data state with one-tap seed actions ("Add your first…") | First-run experience across 12 screens | P1 |
| C12 | **Haptics + undo** — haptic on quick logs; snackbar undo for destructive swipes | Perceived quality | P2 |

## Home tab

- Parity: quick-action buttons row (jump to a sphere log), model selector on the brief card, regenerate button, location/calendar toggles. **P2**
- New: pull-to-refresh brief; brief renders offline from cache with "as of" stamp (cache exists); Today's Focus swipe-to-complete inline. **P2**
- New: "streaks strip" on Home (meditation, detox, reading) for motivation. **P3**

## Health

- Parity: doctors list, menstrual-cycle tracker (female profile), daily stress entry lived here too, conditions list surfaced (profile has it). **P2**
- New: medication reminders at dose times (uses C1); weight trend chart with goal line; water goal adaptive to weather/workouts; lab-result out-of-range highlighting already done — add history per marker. **P1–P2**
- New: HealthKit background delivery so steps/sleep update without opening the app. **P2**

## Finance

- Parity: debts/loans, investments. **P2**
- New: monthly category breakdown chart (donut/bars) — biggest missing visual; upcoming renewals feed Today's Focus; recurring-transaction detection ("this looks monthly — make it a subscription?"); budget month rollover option; CSV import. **P1** for the chart, rest **P2–P3**
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

- Parity: daily affirmation card, streak calendar heatmap, body-scan guide, session notes. **P1** (affirmations are cheap + loved), heatmap **P2**
- New: more breathing patterns (box 4-4-4-4, coherent 5-5) with haptic-guided pacing (no need to look at screen); write mindful minutes to HealthKit (C4); journal prompts from the agent based on recent mood; mood↔sleep correlation insight (cross-sphere, data exists). **P2**

## Rest

- Parity: relaxation section (music/podcast links), detox schedule (not just day toggle). **P3**
- New: **HealthKit sleep auto-import** — kills manual sleep logging, the single biggest UX upgrade in the sphere. **P1**
- New: bedtime wind-down notification from schedule (C1); sleep debt number (target vs 7-day actual); burnout warning surfaced in Today's Focus when work-hours trend high. **P2**

## Travel

- Parity: itinerary notes per trip (we have notes; Flutter grouped past trips timeline). **P3**
- New: MapKit map of visited countries (shaded) — high-delight, low-risk; passport/visa expiry reminders (uses C1); destination weather in trip card near departure; packing template library by trip type (we have per-type checklists — promote to editable templates). **P2**
- New: trip countdown widget option. **P3**

## Home sphere

- Parity: appliances (warranty/purchase), utilities meters/bills, renovation projects, home inventory. **P2** (appliances+utilities), **P3** (renovation, inventory)
- New: recurring chores (weekly cleaning auto-respawn) — biggest practical gap; plant watering notification (C1); shopping list on the Watch (check off in the store!). **P1** (recurring chores), **P2** (watch list)

## Creativity

- Parity: portfolio gallery, project work sessions (time tracking + weekly chart). **P2**
- New: session timer with per-project totals (feeds Life Score genuinely); idea→project one-tap promotion; attach photos to inspiration items. **P2–P3**

## Hobbies

- Parity: fully ported (charts slightly richer in Flutter). 
- New: session timer (start/stop, not just manual minutes); "behind weekly target" nudge into Today's Focus; equipment wishlist with prices linked to Finance savings goal. **P2–P3**

## Relationships

- Parity: contact detail editing sheet polish. **P2**
- New: **import from iOS Contacts** (names + birthdays) — removes the cold-start wall, biggest win in the sphere. **P1**
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
| N1 | **Universal quick capture** — one "+" field (and Share/Action extension): type or dictate "coffee 4.50, mood 4, ran 5k"; the local agent routes it through existing sphere tools | Kills logging fatigue, reuses SphereToolRegistry as-is | P1 |
| N2 | **Cross-sphere correlation insights** — weekly on-device stats over day-keyed data: "mood averages +1.2 on workout days", "spending spikes on poor-sleep days" | Impossible for single-sphere apps; data already exists | P1 |
| N3 | **Proactive agent** — pattern-triggered check-ins (stress up 3 days + no meditation → gentle suggestion), budget cap approaching, streak about to lapse | The "companion" promise made real; needs notification engine | P2 |
| N4 | **Forgiveness mechanics everywhere** — sick mode / vacation mode pauses ALL streaks and softens Life Score; streak freeze tokens | Research-backed churn killer; humane by design | P1 |
| N5 | **Weekly narrative review** — agent writes the story of your week across spheres + one reflective question; saved as a journal artifact | Insight > raw data; retention ritual | P2 |
| N6 | **Life Wheel audit (quarterly)** — user self-rates all 12 spheres 1–10; delta vs computed Life Score is the insight ("you feel worse about Finance than your data says") | Classic coaching tool, perfect fit for the 12-sphere model | P2 |
| N7 | **Privacy as a feature** — local-first + Face ID + explicit "your data never leaves the device except your own LLM key" screen | Users now ask for E2E/privacy explicitly; we already are this — say it | P1 |

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

1. C6 Face ID lock + C7 data export (trust foundation, small)
2. C1 notifications engine (water/meds/bedtime/plants/renewals/brief)
3. C2+C3 App Intents: interactive widget + Siri quick logs
4. Rest: HealthKit sleep auto-import
5. Relationships: iOS Contacts import
6. Finance: monthly category chart; Home sphere: recurring chores
7. C11 empty states + Mindfulness affirmations (cheap delight)
8. C9 SphereUI uk localization (mechanical, pre-launch)
9. C4 HealthKit write-back
10. Learning: Pomodoro + Live Activity (post-launch headline feature)

Phases 8 (CloudKit) and 9 (Engram v2) remain post-launch as planned; C7
export is the interim answer to data safety.
