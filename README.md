# Sphere (iOS)

Native SwiftUI rewrite of [Sphere](https://github.com/TAIPANBOX/sphere) — a
Personal Life Intelligence System with 12 life-sphere AI agents and on-device
cognitive memory (Engram).

Rewrite plan: `../sphere/planning/IOS_REWRITE_PLAN.md`

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
- [ ] App target (iOS 17+), Widget, Watch

## Development

```bash
cd SphereCore
swift test
```
