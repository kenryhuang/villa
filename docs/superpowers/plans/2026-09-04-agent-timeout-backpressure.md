# Agent Timeout Backpressure Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Stop Provider timeout storms by increasing the per-round budget, bounding event context, removing duplicated market state, and restarting automatic scheduling from terminal completion time.

**Architecture:** `AgentContextProjection` creates a bounded model-facing view while `AgentPerceptionInbox` retains the complete frozen delivery batch. `AgentScheduler` applies completion-time backpressure without delaying explicit queued events. Provider timeout remains configuration-driven and per round.

**Tech Stack:** Godot 4.7 GDScript, Node.js 24 TypeScript, JSON configuration, Node test runner.

---

### Task 1: Set the Provider round budget to 60 seconds

**Files:**
- Modify: `services/agent-service/src/config.ts`
- Modify: `services/agent-service/config/agent-service.example.json`
- Modify: `services/agent-service/config/agent-service.local.json` (ignored local configuration)
- Modify: `services/agent-service/tests/config.test.ts`

- [x] **Step 1: Add a failing default-timeout assertion**

Remove `timeout_ms` from a temporary valid configuration and assert `loadConfigFile(...).provider.timeoutMs === 60_000`.

- [x] **Step 2: Verify RED**

Run `node --experimental-strip-types --test tests/config.test.ts`. Expected: actual default is 10,000.

- [x] **Step 3: Change defaults and configuration**

Set the parser default, tracked example, and ignored local configuration to `60000`.

- [x] **Step 4: Verify GREEN**

Run the focused configuration test. Expected: all configuration tests pass.

### Task 2: Bound the model-facing event projection

**Files:**
- Modify: `scripts/ai_agent/agent_context_projection.gd`
- Modify: `tests/test_agent_perception_projection.gd`

- [x] **Step 1: Add failing projection tests**

Project 40 ordered events. Assert `public_world_state` omits nested `market_summary`; `own_event_delta` has exactly 16 records; record zero is `EventDeltaSummary`; summary counts and sequence bounds are deterministic; records 1–15 are the newest raw events. Assert acknowledgement consumes all 40 and release restores the same bounded projection.

- [x] **Step 2: Verify RED**

Run the Godot Agent suite. Expected: the current projection emits all 40 events and keeps nested market state.

- [x] **Step 3: Implement deterministic compaction**

Keep the latest 15 raw events. Summarize the omitted prefix into sorted `event_type_counts` and `aggregate_type_counts`, plus omitted count and sequence/time bounds. Build from the complete result of `freeze_delta`; do not alter inbox storage or cursor behavior.

- [x] **Step 4: Verify GREEN**

Run the Godot Agent suite. Expected: all checks pass.

### Task 3: Apply completion-time scheduler backpressure

**Files:**
- Modify: `scripts/ai_agent/agent_scheduler.gd`
- Modify: `tests/test_agent_runtime.gd`

- [x] **Step 1: Add failing success/failure timing tests**

Dispatch an Agent, advance game time while it is in flight, then complete or fail it. Assert no automatic catch-up occurs until one full role interval after the terminal callback. Also assert an explicit queued priority event still dispatches immediately.

- [x] **Step 2: Verify RED**

Run the Godot Agent suite. Expected: current `_last_dispatched` remains at request-start time and dispatches catch-up immediately.

- [x] **Step 3: Reset the automatic baseline on terminal callback**

In `_on_gateway_response`, assign `_last_dispatched[agent_id] = _current_minute` before handling any explicit pending item. Preserve current success, failure, dialogue replacement, and pending-event behavior.

- [x] **Step 4: Verify GREEN**

Run the Godot Agent suite. Expected: all checks pass.

### Task 4: Full and connected verification

**Files:**
- Modify: `docs/superpowers/plans/2026-09-04-agent-timeout-backpressure.md`

- [x] **Step 1: Run offline suites**

Run `npm test` and `godot_console --headless --path . --script res://tests/run_agent_system_tests.gd`. Expected: zero failures.

- [x] **Step 2: Restart the configured service**

Verify and stop only the Node process listening on `127.0.0.1:8787`, then start current source with the local JSON configuration and hidden window.

- [x] **Step 3: Run connected tests**

Run `agent_service_integration.gd` and `agent_runtime_service_integration.gd`. Expected: both pass and the service stderr log remains empty.

- [x] **Step 4: Inspect trace and diff**

Confirm the new trace contains a completed real Runtime request, run `git diff --check`, and ensure no generated logs, databases, credentials, or `.gd.uid` files appear in Git status.
