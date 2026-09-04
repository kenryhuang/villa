# Agent Provider Concurrency and Context Dedup Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Reduce autonomous Agent timeout pressure by using a 180-second per-round budget, two globally shared Provider slots, doubled default schedules, and non-duplicated event projections.

**Architecture:** The shared `OpenAICompatibleProvider` owns a fair FIFO gate and acquires one slot immediately before each remote call; the existing per-round timer starts only inside that slot. Godot keeps complete frozen inbox batches but filters event IDs already present in the public window before producing the bounded model-facing delta.

**Tech Stack:** TypeScript/Node HTTP and test runner, Godot 4/GDScript, JSON configuration.

---

### Task 1: Provider timeout and configuration

**Files:**
- Modify: `services/agent-service/src/config.ts`
- Modify: `services/agent-service/config/agent-service.example.json`
- Modify: `services/agent-service/config/agent-service.local.json`
- Modify: `services/agent-service/tests/config.test.ts`

- [x] Add failing assertions that the omitted timeout defaults to `180_000`, `max_concurrency` defaults to `2`, and explicit concurrency is loaded and range-checked.
- [x] Run `npm test -- --test-name-pattern="Provider|configuration"` and confirm the new assertions fail against the 60-second configuration without concurrency.
- [x] Add `ProviderConfig.maxConcurrency`, accept `provider.max_concurrency`, use a `180_000` timeout default with a range that includes it, and update tracked/local JSON values.
- [x] Re-run the focused tests and confirm they pass.

### Task 2: Global FIFO Provider gate

**Files:**
- Create: `services/agent-service/src/provider_concurrency_gate.ts`
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `services/agent-service/src/provider.ts`

- [x] Add a failing Provider integration test proving a two-slot gate never starts a third operation concurrently, grants queued work FIFO, and starts a Provider timeout only after a slot is granted.
- [x] Run the focused concurrency test and confirm the old implementation reaches three simultaneous Provider calls.
- [x] Implement a gate whose `run(signal, operation)` waits for a permit, removes cancelled queued work, then invokes the operation and always releases the permit in `finally`.
- [x] Wrap each decision `/chat/completions` round and each memory-compaction request with the shared gate, placing `withProviderTimeout(...)` inside `gate.run(...)`.
- [x] Re-run concurrency and Provider tests and confirm they pass.

### Task 3: Schedule defaults and event projection merge

**Files:**
- Modify: `data/agents/roles.json`
- Modify: `scripts/ai_agent/agent_context_projection.gd`
- Modify: `tests/test_agent_runtime.gd`
- Modify: `tests/test_agent_perception_projection.gd`
- Modify: `tests/test_agent_main_integration.gd`

- [x] Add failing assertions for farmer `[2,2]`, merchant `[2,4]`, explorer `[4,8]`, and for public event IDs being absent from `own_event_delta` while private/older events remain.
- [x] Run the Godot Agent suite and confirm failures show the old intervals and duplicated events.
- [x] Double the authored role ranges. In `build`, capture the public window once, build its non-empty event-ID set, filter the frozen delta against it, then apply the existing deterministic 16-record compaction.
- [x] Keep acknowledgement/release attached to the untouched frozen inbox batch and update integration expectations accordingly.
- [x] Re-run the Godot Agent suite and confirm it passes.

### Task 4: Full verification

**Files:**
- Modify: `services/agent-service/README.md`
- Modify: `docs/superpowers/specs/2026-09-04-agent-timeout-backpressure-design.md`

- [x] Document `timeout_ms: 180000`, `max_concurrency: 2`, doubled role defaults, and event de-duplication.
- [x] Run `npm test` and require zero failures.
- [x] Run `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd` and require zero failures.
- [x] Run `git diff --check` and inspect `git status --short` so ignored credentials and runtime traces are not staged.
