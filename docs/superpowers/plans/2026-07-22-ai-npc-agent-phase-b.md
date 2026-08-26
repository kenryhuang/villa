# AI NPC Agent Phase B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the Phase A mock decision for one peaceful Villager with a Loom-backed remote Agent that has identity, bounded tools, short-term memory, and mixed structured/free-text dialogue.

**Architecture:** The service adapts a pinned Loom package behind `NpcLoop`, stores one Agent profile and bounded memory in SQLite, and uses an OpenAI-compatible provider only when configured. Godot attaches the existing Phase A controller to one Villager and retains deterministic fallback and authority.

**Tech Stack:** Phase A protocol, TypeScript/Node.js, pinned Loom dependency, SQLite, OpenAI-compatible Chat Completions, Godot 4.7.

**Configuration migration note (2026-08-26):** Current Agent service and Godot client settings use the ignored JSON files documented in `services/agent-service/README.md`. The tentative process-level configuration in this historical proposal is superseded.

## Global Constraints

- Production dependencies contain no machine-local absolute paths.
- One decision has at most 3 ReAct rounds and 6 tool calls.
- Autonomous timeout is 3 seconds; dialogue timeout is 10 seconds.
- Free text cannot directly grant resources, complete quests, or commit trades.
- Provider keys remain server-side and automated tests use a scripted provider.
- Phase A fallback remains functional with the service stopped.
- Service verification command is `npm --prefix services/agent-service test && npm --prefix services/agent-service run typecheck && npm --prefix services/agent-service run build`.
- Godot verification command is `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`.

---

### Task 1: Versioned Loom adapter

**Files:** Create `services/agent-service/src/loom/npc-context.ts`, `npc-loop.ts`, `scripted-provider.ts`, `services/agent-service/tests/npc-loop.test.ts`; modify `services/agent-service/package.json` and `package-lock.json`.

**Interfaces:** `makeNpcContext(profile, snapshot, memory, budget)`, `runNpcLoop(context, tools, provider, signal)`, and `ScriptedProvider`.

- [ ] Write failing tests mapping identity/goal/knowledge/affordances, enforcing 3 rounds/6 tools, timeout cancellation, and final protocol action conversion.
- [ ] Run targeted Vitest and verify RED.
- [ ] Add Loom as a pinned package/workspace dependency and implement an adapter rather than importing internal source paths. Reject loop output that is not a Phase A action envelope.
- [ ] Run tests/typecheck and commit `feat: adapt Loom for villager decisions`.

### Task 2: Agent profile and bounded short-term memory

**Files:** Create `services/agent-service/src/agents/profile.ts`, `src/memory/memory-repository.ts`, `src/memory/sqlite-memory-repository.ts`, `data/agents/blacksmith-zhang.json`, and `tests/memory-repository.test.ts`.

**Interfaces:** `AgentProfileRepository.get(npcId)`, `MemoryRepository.recent(agentId, limit)`, `append`, `dialogue`, and `compact`; exact caps are 24 observations and 12 dialogue turns.

- [ ] Write failing repository contract tests for isolation by `save_id+npc_id`, stable order, caps, expiry, restart persistence, and profile constraints.
- [ ] Run tests and verify RED.
- [ ] Implement SQLite transactions and the first versioned profile with role, personality, values, constraints, goals, and allowed tools. Never store provider secrets in the database.
- [ ] Run repository tests/typecheck and commit `feat: persist bounded villager memory`.

### Task 3: Snapshot tools and real provider configuration

**Files:** Create `services/agent-service/src/tools/snapshot-tools.ts`, `src/providers/provider-factory.ts`, `tests/snapshot-tools.test.ts`, `tests/provider-factory.test.ts`; modify `src/server.ts`.

**Interfaces:** Tools `inspect_visible_objects`, `inspect_local_inventory`, `inspect_relationship`, `recall_recent_events`, `recall_long_term_memory`, `inspect_schedule`, `inspect_active_quests`; `createProvider(config)`.

- [ ] Write failing tests for tool allowlists, unavailable private data, malformed arguments, cancellation, missing-key startup, and custom base URL.
- [ ] Run tests and verify RED.
- [ ] Implement read-only tools over supplied snapshot/memory. Provider selection requires `provider.api_key`, `provider.model`, and `provider.base_url` in the local service JSON; the current runtime has no mock Provider mode.
- [ ] Run tests/typecheck and commit `feat: add bounded villager tools and provider`.

### Task 4: Mixed dialogue API

**Files:** Create `services/agent-service/src/dialogue/dialogue-service.ts`, `tests/dialogue-service.test.ts`; modify `src/api/app.ts`, `shared/agent_protocol/v1/fixtures/dialogue-request.json`, `dialogue-response.json`, `scripts/agents/agent_protocol.gd`, and `tests/test_agent_protocol.gd`.

**Interfaces:** `POST /v1/npcs/:npc_id/dialogue`; response contains `speech{text,emotion}`, `suggested_choices[]`, and optional `proposal`.

- [ ] Write failing tests for structured choice semantics, free-text untrusted delimiter, 280-character speech limit, forbidden direct rewards, optional proposal, idempotency, and 10-second timeout.
- [ ] Run TypeScript and Godot contract tests; verify RED.
- [ ] Implement dialogue prompt/context and strict response schema. A proposal contains template and parameters only; no game mutation.
- [ ] Run both suites and commit `feat: add mixed AI villager dialogue`.

### Task 5: Attach one Agent Villager

**Files:** Modify `scripts/actors/villager.gd`, `scripts/systems/villager_system.gd`, `scripts/ui/dialogue_ui.gd`, one villager resource/scene; create `tests/test_agent_villager_integration.gd`.

**Interfaces:** Consume Phase A `NpcAgentController`; Villager exposes the five action methods and dialogue proposal confirmation.

- [ ] Write failing tests proving AI actions call deterministic Villager methods, rejected proposals do not mutate state, confirmed authored choice invokes the relevant system, and disconnected service uses authored dialogue/schedule.
- [ ] Run Godot tests and verify RED.
- [ ] Enable Agent mode only for the Plan 5 villager `blacksmith_zhang`; all other villagers remain deterministic. Route free-text through controller and keep structured choices authoritative.
- [ ] Run Godot tests, Mock Service integration, and manual real-provider smoke only when credentials are present; commit `feat: connect one villager to remote agent`.

### Task 6: Phase B acceptance

**Files:** Create `tests/agent_phase_b_acceptance.gd`, `services/agent-service/tests/phase-b.acceptance.test.ts`, update service README.

- [ ] Verify scripted-provider tool loop, memory survival across service restart, structured/free dialogue, proposal confirmation, timeout fallback, and no direct game-state write.
- [ ] Run service typecheck/tests/build, Godot full suite, connected integration, disconnected fallback, and main launch.
- [ ] Record opt-in real-provider command without embedding keys; commit `test: verify one Loom-backed villager`.
