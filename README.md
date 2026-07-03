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
  reinforcement, Ebbinghaus decay + pruning (24 tests)
- [ ] LLM engines (Anthropic native + OpenAI-compatible)
- [ ] AgentService + sphere tools
- [ ] App target (iOS 17+), Widget, Watch

## Development

```bash
cd SphereCore
swift test
```
