# AI NPC Agent Phase C Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Expand the proven single Agent to every villager with tiered scheduling, persistent long-term summaries, save checkpoints, global budgets, and trace observability.

**Architecture:** An Agent Registry isolates profiles and memory by save/NPC, while Godot and service schedulers cooperate on P0–P3 priority. Checkpoints make Godot authoritative, and traces expose decisions without revealing hidden chain-of-thought.

**Tech Stack:** Phase B service/Godot integration, SQLite/PostgreSQL repository abstraction, Godot debug UI.

## Global Constraints

- P0 immediate; P1 every 5–15 seconds or event; P2 each game hour/major event; P3 no LLM.
- One in-flight request per NPC and duplicate events are coalesced.
- Short-term memory remains capped at 24 observations and 12 dialogue turns.
- Checkpoint conflicts resolve in favor of Godot by creating a new server memory version.
- Traces store summaries, tools, outcomes, latency, tokens, and cost, not hidden model reasoning.
- Every service task runs `npm --prefix services/agent-service test && npm --prefix services/agent-service run typecheck`.
- Every Godot task runs `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`.

---

### Task 1: Multi-Agent Registry

**Files:** Create `services/agent-service/src/agents/agent-registry.ts`, `src/storage/migrations/002-agent-registry.sql`, `data/agents/*.json`, and `tests/agent-registry.test.ts`.

- [ ] Test isolation, lazy load, unload/reload, missing profile, concurrent get, and 20-agent enumeration.
- [ ] Implement key `save_id:npc_id`, per-Agent serialization lock, and repository-backed profiles/memory.
- [ ] Run tests/typecheck and commit `feat: add isolated villager agent registry`.

### Task 2: P0–P3 scheduling and coalescing

**Files:** Create `services/agent-service/src/scheduling/budget-scheduler.ts`, `tests/budget-scheduler.test.ts`, `scripts/agents/agent_scheduler.gd`, `tests/test_agent_scheduler.gd`; modify `tests/run_tests.gd`.

**Interfaces:** `classify(npc, player, events) -> priority`, `enqueue`, `cancel`, `tick`; service `acquire(saveId,npcId,priority,budget)`.

- [ ] Test exact priority conditions, P1 seeded 5–15 second jitter, P2 hourly gate, P3 suppression, event coalescing, cancellation, and one in-flight request.
- [ ] Implement deterministic seeded scheduling in Godot and fair priority/concurrency queue in service.
- [ ] Run suites and commit `feat: schedule full-village agent decisions`.

### Task 3: Long-term summaries and relationship memory

**Files:** Create `services/agent-service/src/memory/memory-summarizer.ts`, `src/storage/migrations/003-long-term-memory.sql`, `tests/memory-summarizer.test.ts`; modify `src/agents/decision-store.ts`.

- [ ] Test importance threshold, source IDs, confidence, deduplication, failed-summary rollback, and preservation of promises/quest facts.
- [ ] Implement scripted-provider-compatible structured summaries and deterministic fallback summarizer; do not summarize ordinary duplicate observations.
- [ ] Run tests and commit `feat: summarize persistent villager memories`.

### Task 4: Session sync and Godot checkpoints

**Files:** Modify `services/agent-service/src/api/app.ts`, `src/protocol/types.ts`, `src/protocol/schemas.ts`, `scripts/core/save_manager.gd`, `scripts/agents/agent_gateway.gd`; create `shared/agent_protocol/v1/fixtures/session-sync.json`, `checkpoint.json`, `services/agent-service/tests/session-sync.test.ts`, `tests/test_agent_checkpoint.gd`.

- [ ] Test initial sync, same-cursor no-op, service-ahead conflict, Godot-ahead restore, repeated checkpoint idempotency, and offline queued checkpoint.
- [ ] Save profile version, long-term summaries, relations, goals, commitments, and cursor. On conflict create a new server version from Godot data and retain old version for traceability.
- [ ] Run contract/Godot/save tests and commit `feat: synchronize villager agent checkpoints`.

### Task 5: Token/cost budgets and trace UI

**Files:** Create `services/agent-service/src/scheduling/budget-policy.ts`, `src/observability/trace-repository.ts`, `tests/budget-policy.test.ts`, `scripts/ui/agent_debug_ui.gd`, `scenes/ui/agent_debug_ui.tscn`, `tests/test_agent_debug_ui.gd`; modify service API and `tests/run_tests.gd`.

- [ ] Test per-decision, per-NPC, and per-save ceilings; 429 backoff; fallback transition; trace redaction; filters by NPC/decision/outcome.
- [ ] Implement budget accounting from provider usage and a development-only UI showing goal, observations, tool names, decision summary, action outcomes, latency, tokens, and cost.
- [ ] Run tests and commit `feat: add agent budgets and decision traces`.

### Task 6: Full-village load acceptance

**Files:** Create `services/agent-service/tests/full-village-load.test.ts`, `tests/agent_scheduler_acceptance.gd`; modify `services/agent-service/README.md`.

- [ ] Simulate 20, 50, and 100 logical NPCs using scripted provider; assert no per-NPC overlap, P0 latency priority, P3 zero calls, bounded queues, and memory isolation.
- [ ] Run disconnected Godot fallback with all villagers and verify deterministic schedules.
- [ ] Run all suites/build/main launch and commit `test: verify full-village agent scheduling`.
