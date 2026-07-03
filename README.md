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
- [ ] App target (iOS 17+), Widget, Watch

## Development

```bash
cd SphereCore
swift test
```
