# Role-Based AI NPC Agent Framework Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Deliver three role-based AI NPC Agents backed by a configurable real Provider, independent SQLite memory, game-time scheduling, dialogue, and headless actions that really mutate Godot-owned farm, inventory, market, building, activity, and discovery state.

**Architecture:** Godot remains the only world authority and sends immutable role-filtered snapshots to a local TypeScript Agent Service. The service assembles Soul/goals/memory/tool context, calls an OpenAI-compatible Provider, and returns one structured command; Godot validates and atomically commits it. Runtime memory lives in SQLite and is exported as a save sidecar.

**Tech Stack:** Godot 4.7/GDScript, Node.js 24, TypeScript 5, Node built-in HTTP/fetch and `node:sqlite`, OpenAI-compatible tool-calling HTTP API, repository SceneTree test harness.

---

## File map

Service files are focused by responsibility:

- `services/agent-service/src/protocol.ts`: closed request/response/tool types and runtime validation.
- `services/agent-service/src/config.ts`: environment-only Provider and service configuration.
- `services/agent-service/src/provider.ts`: real OpenAI-compatible Provider adapter.
- `services/agent-service/src/agents.ts`: role/profile registry and prompt/context construction.
- `services/agent-service/src/memory.ts`: per-save, per-Agent SQLite event and long-term memory repository.
- `services/agent-service/src/app.ts`: HTTP routing and idempotent request handling.
- `services/agent-service/src/server.ts`: process entry point.

Godot files keep world state and orchestration separate:

- `scripts/ai_agent/agent_protocol.gd`: strict response parsing and request construction.
- `scripts/ai_agent/agent_registry.gd`: role/profile configuration and Agent-managed IDs.
- `scripts/ai_agent/agent_gateway.gd`: HTTP lifecycle and epoch cancellation.
- `scripts/ai_agent/agent_perception_inbox.gd`: EventBus filtering/coalescing.
- `scripts/ai_agent/agent_scheduler.gd`: absolute-game-minute scheduling and backpressure.
- `scripts/ai_agent/agent_action_validator.gd`: permission/schema/revision validation.
- `scripts/ai_agent/agent_action_executor_router.gd`: one-command real execution and idempotency.
- `scripts/systems/npc_farm_registry.gd`: NPC plot/crop authority.
- `scripts/systems/npc_building_registry.gd`: headless NPC building authority.
- `scripts/systems/npc_activity_system.gd`: timed travel/build activity authority.
- `scripts/systems/explorer_knowledge_registry.gd`: private/public discovery authority.

### Task 1: Shared protocol and TypeScript service scaffold

**Files:**
- Create: `services/agent-service/package.json`
- Create: `services/agent-service/tsconfig.json`
- Create: `services/agent-service/src/protocol.ts`
- Create: `services/agent-service/tests/protocol.test.ts`
- Create: `shared/agent_protocol/v1/decision-request.json`
- Create: `shared/agent_protocol/v1/action-intent.json`
- Create: `shared/agent_protocol/v1/action-outcome.json`
- Modify: `.gitignore`

- [ ] **Step 1: Write the failing protocol tests**

Test valid fixtures and rejection of wrong protocol, missing IDs, negative revision, more than one command, unknown status, and non-object arguments:

```ts
assert.equal(parseDecisionRequest(validRequest).ok, true);
assert.equal(parseDecisionRequest({...validRequest, protocol_version: 2}).ok, false);
assert.equal(parseActionIntent({...validIntent, tool_name: "change_gold"}, ["wait"]).ok, false);
assert.equal(parseActionOutcome({...validOutcome, status: "maybe"}).ok, false);
```

- [ ] **Step 2: Run RED**

Run: `npm --prefix services/agent-service test -- tests/protocol.test.ts`  
Expected: FAIL because the package and protocol module do not exist.

- [ ] **Step 3: Add exact protocol contracts and validators**

Define protocol version `1` and these closed envelopes:

```ts
export type Trigger = "schedule" | "event" | "dialogue" | "catch_up";
export type OutcomeStatus = "accepted" | "in_progress" | "completed" | "rejected" | "failed";
export interface DecisionRequest {
  protocol_version: 1; request_id: string; session_id: string; session_epoch: number;
  agent_id: string; trigger: Trigger; game_minute: number; world_revision: number;
  snapshot: Record<string, unknown>; event_delta: readonly Record<string, unknown>[];
  dialogue_input?: string;
}
export interface ActionIntent {
  protocol_version: 1; decision_id: string; request_id: string; agent_id: string;
  expected_revision: number; idempotency_key: string; tool_name: string;
  tool_version: 1; arguments: Record<string, unknown>; speech?: string;
  decision_summary: string;
}
export interface ActionOutcome {
  protocol_version: 1; decision_id: string; idempotency_key: string;
  status: OutcomeStatus; failure_code?: string; committed_revision: number;
  changed_entities: readonly string[]; resource_delta: Record<string, number>;
  hud_message: string; game_minute: number;
}
```

Use dependency-free runtime guards. Set `package.json` scripts to Node 24 type stripping:

```json
{"type":"module","scripts":{"test":"node --experimental-strip-types --test tests/*.test.ts","start":"node --experimental-strip-types src/server.ts"},"engines":{"node":">=24"}}
```

- [ ] **Step 4: Run GREEN**

Run: `npm --prefix services/agent-service test -- tests/protocol.test.ts`  
Expected: all protocol tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add .gitignore services/agent-service shared/agent_protocol/v1
git commit -m "feat: define role agent protocol"
```

### Task 2: Real Provider, roles, Soul, tools, and context

**Files:**
- Create: `services/agent-service/src/config.ts`
- Create: `services/agent-service/src/provider.ts`
- Create: `services/agent-service/src/agents.ts`
- Create: `services/agent-service/tests/provider.test.ts`
- Create: `services/agent-service/tests/agents.test.ts`
- Create: `data/agents/roles.json`
- Create: `data/agents/profiles.json`

- [ ] **Step 1: Write failing Provider and profile tests**

Use a local Node HTTP server as the protocol test double. Assert missing environment variables fail fast, API keys stay in headers, tool schemas are role-filtered, and a valid Provider response becomes one `ActionIntent`:

```ts
assert.throws(() => loadConfig({}), /AGENT_PROVIDER_API_KEY/);
assert.deepEqual(registry.get("lao_li").tools.includes("plant"), false);
assert.deepEqual(registry.get("farmer_ahe").tools.includes("plant"), true);
assert.equal((await provider.decide(request, context)).tool_name, "plant");
```

- [ ] **Step 2: Run RED**

Run: `npm --prefix services/agent-service test -- tests/provider.test.ts tests/agents.test.ts`  
Expected: missing modules.

- [ ] **Step 3: Implement configuration and the real adapter**

Read `AGENT_PROVIDER_BASE_URL`, `AGENT_PROVIDER_API_KEY`, `AGENT_PROVIDER_MODEL`, optional timeout/token/temperature values, and never serialize the key. POST an OpenAI-compatible tool-calling request to `${baseUrl}/chat/completions`; pass identity, Soul, goals, snapshot, event delta, recalled memory, and role tool definitions. Accept only one command tool call or a `wait` result. Abort on timeout and reject plain-text commands.

Create exact profiles:

```json
[
  {"agent_id":"farmer_ahe","npc_id":"farmer_ahe","role":"farmer","gold":500,"inventory":{"grain_seed":8,"carrot_seed":6,"potato_seed":6}},
  {"agent_id":"lao_li","npc_id":"lao_li","role":"merchant","resource_ledger":"npc_economy"},
  {"agent_id":"xuezhe_lin","npc_id":"xuezhe_lin","role":"explorer","inventory_add":{"rope":2,"bread":2}}
]
```

Role command allowlists are:

```ts
farmer: ["till", "plant", "harvest", "build", "buy", "sell", "speak", "wait"]
merchant: ["buy", "sell", "propose_trade", "speak", "wait"]
explorer: ["prepare_supplies", "travel", "survey", "collect_sample", "register_discovery", "sell", "speak", "wait"]
```

- [ ] **Step 4: Run GREEN**

Run: `npm --prefix services/agent-service test -- tests/provider.test.ts tests/agents.test.ts`  
Expected: tests PASS and captured Authorization header equals `Bearer test-key` without appearing in body.

- [ ] **Step 5: Commit**

```powershell
git add services/agent-service/src services/agent-service/tests data/agents
git commit -m "feat: add configurable real agent provider"
```

### Task 3: SQLite memory, decisions, outcomes, and checkpoints

**Files:**
- Create: `services/agent-service/src/memory.ts`
- Create: `services/agent-service/src/app.ts`
- Create: `services/agent-service/src/server.ts`
- Create: `services/agent-service/tests/memory.test.ts`
- Create: `services/agent-service/tests/app.test.ts`
- Create: `services/agent-service/README.md`

- [ ] **Step 1: Write failing repository and HTTP tests**

Cover isolation by `session_id + agent_id`, event ordering, deterministic importance scoring, 20-candidate compaction eligibility, outcome idempotency, and checkpoint export/import. Exercise:

```text
GET  /health
POST /v1/sessions/sync
POST /v1/agents/:id/decide
POST /v1/agents/:id/outcomes
POST /v1/checkpoints/export
POST /v1/checkpoints/import
```

Assert repeated outcome keys insert one event and checkpoint restore brings back only the selected session.

- [ ] **Step 2: Run RED**

Run: `npm --prefix services/agent-service test -- tests/memory.test.ts tests/app.test.ts`  
Expected: missing repository/app modules.

- [ ] **Step 3: Implement SQLite and HTTP service**

Use `DatabaseSync` from `node:sqlite` and tables `events`, `long_term_memories`, `idempotency`, and `sessions`. Score events from goal impact, resource magnitude, relationship/discovery flags, failure, and novelty. Append raw events immediately. Expose FTS5 recall; if FTS5 creation is unavailable, fail service startup with a clear error.

The decide route loads the Agent profile and relevant memories, calls the real Provider, validates the allowed tool, stores the decision event, and returns the intent. The outcomes route is idempotent and stores resource deltas. Export uses SQLite backup/copy to a requested safe checkpoint directory; import accepts only a checkpoint created by the service and matching checksum/session metadata.

- [ ] **Step 4: Run GREEN**

Run: `npm --prefix services/agent-service test`  
Expected: all service tests PASS without public network or real credentials; Provider tests use only their local HTTP endpoint.

- [ ] **Step 5: Commit**

```powershell
git add services/agent-service
git commit -m "feat: persist independent agent memories"
```

### Task 4: Godot Agent protocol and authoritative role registries

**Files:**
- Create: `scripts/ai_agent/agent_protocol.gd`
- Create: `scripts/ai_agent/agent_registry.gd`
- Create: `scripts/systems/npc_farm_registry.gd`
- Create: `scripts/systems/npc_building_registry.gd`
- Create: `scripts/systems/npc_activity_system.gd`
- Create: `scripts/systems/explorer_knowledge_registry.gd`
- Create: `tests/test_agent_world_state.gd`
- Create: `tests/run_agent_system_tests.gd`
- Modify: `scripts/core/game_data.gd`

- [ ] **Step 1: Write failing Godot tests**

Test strict fixture parsing; default profiles; 12 farmer plots; planting consumes no inventory inside the farm registry; mature harvest clears the plot; timed travel completes once; private discoveries do not appear publicly until registered; all `to_dict/from_dict` methods reject malformed input atomically.

```gdscript
assertions.truthy(farm.till("farmer_ahe", 0), "farmer tills own plot")
assertions.truthy(farm.plant("farmer_ahe", 0, "carrot", 120, 180), "farmer plants")
assertions.equal(farm.harvest("farmer_ahe", 0, 179), {}, "immature harvest rejects")
assertions.equal(farm.harvest("farmer_ahe", 0, 180).item_id, "carrot", "mature harvest returns crop")
```

- [ ] **Step 2: Run RED**

Run: `godot --headless --path . --script res://tests/run_agent_system_tests.gd`  
Expected: preload errors for missing Agent scripts.

- [ ] **Step 3: Implement focused registries**

Use `RefCounted` registries with explicit `configure`, `to_dict`, `from_dict`, and mutation methods. No registry may access scene visuals. Add `farmer_ahe` to `VILLAGERS` and `NPC_ECONOMY_PROFILES`; add rope/bread to学者林 only through an idempotent migration marker rather than every load.

- [ ] **Step 4: Run GREEN**

Run: `godot --headless --path . --script res://tests/run_agent_system_tests.gd`  
Expected: PASS with no orphan node warnings.

- [ ] **Step 5: Commit**

```powershell
git add scripts/ai_agent scripts/systems data/agents tests scripts/core/game_data.gd
git commit -m "feat: add authoritative NPC agent world state"
```

### Task 5: Validation and real headless command execution

**Files:**
- Create: `scripts/ai_agent/agent_action_validator.gd`
- Create: `scripts/ai_agent/agent_action_executor_router.gd`
- Create: `tests/test_agent_action_execution.gd`
- Modify: `tests/run_agent_system_tests.gd`
- Modify: `scripts/systems/npc_economy_system.gd`

- [ ] **Step 1: Write failing action tests**

Cover unauthorized tools, stale revision, duplicate idempotency, insufficient seed/gold/stock, and successful farmer/merchant/explorer flows. Assert a complete farmer flow changes real state:

```gdscript
var planted := executor.execute(intent("plant", {"plot":0,"seed_item_id":"carrot_seed"}))
assertions.equal(planted.status, "completed", "plant commits")
assertions.equal(npc_state.inventory.carrot_seed, 5, "plant consumes NPC seed")
var harvested := executor.execute(intent("harvest", {"plot":0}, mature_revision))
assertions.equal(npc_state.inventory.carrot, expected_yield, "harvest enters NPC inventory")
```

- [ ] **Step 2: Run RED**

Run the Agent Godot suite. Expected: missing validator/executor.

- [ ] **Step 3: Implement validation and executor routing**

Add public `agent_buy`, `agent_sell`, and `set_agent_managed` methods to `NpcEconomySystem`; reuse its sealed/finalized Market transaction path. `simulate_day` skips autonomous `_simulate_npc` for managed IDs. The executor owns a monotonic revision, caches outcomes by idempotency key, atomically restores touched registries/NPC state/market on failure, and publishes HUD only after success.

Implement command parameter schemas with bounded quantities and known IDs. `speak` and `wait` do not change assets. `travel`/`build` create timed activities; completion applies the result exactly once. `survey` derives results from region definition + stable world seed; Provider text cannot create arbitrary items.

- [ ] **Step 4: Run GREEN and economy regression**

Run:

```powershell
godot --headless --path . --script res://tests/run_agent_system_tests.gd
godot --headless --path . --script res://tests/run_task2_trade_tests.gd
```

Expected: both PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/ai_agent scripts/systems/npc_economy_system.gd tests
git commit -m "feat: execute real headless NPC agent actions"
```

### Task 6: Perception, scheduling, Gateway, and dialogue requests

**Files:**
- Create: `scripts/ai_agent/agent_perception_inbox.gd`
- Create: `scripts/ai_agent/agent_scheduler.gd`
- Create: `scripts/ai_agent/agent_gateway.gd`
- Create: `tests/test_agent_runtime.gd`
- Modify: `tests/run_agent_system_tests.gd`

- [ ] **Step 1: Write failing runtime tests**

Use a fake Gateway object, not a mock Provider. Prove farmer hourly, merchant every 1–2 hours, explorer every 2–4 hours, dialogue immediate, same-item market events coalesce, one request per Agent stays in flight, time jumps produce one catch-up request, and old `session_epoch` responses are ignored.

- [ ] **Step 2: Run RED**

Run the Agent suite. Expected: missing runtime scripts.

- [ ] **Step 3: Implement the runtime**

`AgentPerceptionInbox` receives normalized EventBus records and coalesces by `kind + entity_id`. `AgentScheduler.advance_to(game_minute)` computes due Agents from absolute minutes; it never loops once per missed hour. `AgentGateway` uses `HTTPRequest`, configurable base URL/token/timeout, one in-flight request per Agent, and strict `AgentProtocol` parsing. Successful intents are validated/executed and outcomes POSTed to the service.

- [ ] **Step 4: Run GREEN**

Run the Agent suite. Expected: all cadence, coalescing, timeout, stale-response and dialogue tests PASS.

- [ ] **Step 5: Commit**

```powershell
git add scripts/ai_agent tests
git commit -m "feat: schedule role agents from game events"
```

### Task 7: Main scene, HUD, existing dialogue, and save integration

**Files:**
- Modify: `scripts/main.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/core/event_bus.gd`
- Modify: `scripts/ui/dialogue_ui.gd`
- Create: `tests/test_agent_main_integration.gd`
- Create: `tests/test_agent_save_integration.gd`
- Modify: `tests/run_agent_system_tests.gd`

- [ ] **Step 1: Write failing integration tests**

Assert Main creates the Agent systems, maps老李/学者林/阿禾, routes their dialogue to `trigger_dialogue`, keeps other NPC dialogue unchanged, publishes committed outcomes through `HudMessageBus`, and round-trips all Godot Agent registries through SaveManager. Verify failed/missing memory checkpoint warns but does not block world load.

- [ ] **Step 2: Run RED**

Run the Agent suite. Expected: integration assertions fail before wiring.

- [ ] **Step 3: Wire runtime and persistence**

Instantiate registries/runtime in `_initialize_systems`, configure them after Market/NPC economy, subscribe to `SeasonSystem.time_changed` and EventBus market/agent events, and add阿禾 to the NPC spawn mapping when a scene child exists. Route committed messages as source `agent` with metadata `{agent_id, decision_id, changed_entities}`.

Extend SaveManager with an `agent_world` versioned dictionary. Add a checkpoint coordinator interface; save generations use world JSON + memory sidecar + manifest, while legacy saves continue loading. A missing service checkpoint creates empty service memory and a warning, not a failed world load.

- [ ] **Step 4: Run GREEN and main smoke**

Run:

```powershell
godot --headless --path . --script res://tests/run_agent_system_tests.gd
godot --headless --path . --quit-after 120
```

Expected: Agent suite PASS; main initializes without script errors.

- [ ] **Step 5: Commit**

```powershell
git add scripts/main.gd scripts/core scripts/ui tests
git commit -m "feat: integrate role agents with game runtime"
```

### Task 8: Connected acceptance and final verification

**Files:**
- Create: `tests/agent_service_integration.gd`
- Create: `docs/validation/role-agent-framework-validation.md`
- Modify: `services/agent-service/README.md`

- [ ] **Step 1: Add a connected protocol acceptance script**

The SceneTree script sends a deterministic snapshot to the running service, validates one intent, POSTs an outcome, exports a checkpoint, and prints `PASS: role agent service integration`. It reads service URL/token from environment and skips with an explicit message when no real Provider credentials are configured.

- [ ] **Step 2: Run all offline verification**

```powershell
npm --prefix services/agent-service test
godot --headless --path . --script res://tests/run_agent_system_tests.gd
godot --headless --path . --script res://tests/run_task2_trade_tests.gd
godot --headless --path . --script res://tests/run_economy_save_integration_tests.gd
godot --headless --path . --quit-after 120
```

Expected: all commands exit `0`.

- [ ] **Step 3: Run opt-in real Provider smoke**

Start the service with `AGENT_PROVIDER_BASE_URL`, `AGENT_PROVIDER_API_KEY`, and `AGENT_PROVIDER_MODEL`, then run `tests/agent_service_integration.gd`. Expected: health succeeds, a role-allowed structured intent returns, outcome persists, and checkpoint export succeeds. Never print credential values.

- [ ] **Step 4: Record evidence and commit**

Document commands, exit codes, test counts, skipped credential-dependent smoke, and known visual non-goals in `docs/validation/role-agent-framework-validation.md`.

```powershell
git add tests/agent_service_integration.gd services/agent-service/README.md docs/validation/role-agent-framework-validation.md
git commit -m "test: validate role-based NPC agents"
```

## Completion gate

- All service and Godot offline tests pass.
- The service never starts without a complete real Provider configuration.
- Tests use fake HTTP endpoints only; runtime includes no mock Provider.
- 阿禾, 老李, and 学者林 have distinct Soul/goals/tools/memory namespaces.
- Successful commands mutate Godot authority and emit HUD outcome messages.
- Failed, stale, duplicate, or unauthorized commands do not mutate assets.
- Save/load restores Agent world state; missing memory sidecar degrades safely.
- Worktree is clean after the final commit.
