# AI NPC Agent Phase A Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a deterministic local vertical slice in which Godot sends a filtered NPC world snapshot to a TypeScript Mock Agent Service, validates and executes the returned action plan, reports outcomes, and falls back safely when the service fails.

**Architecture:** A versioned JSON contract is shared through schemas and fixtures. The TypeScript service owns HTTP/idempotency and a deterministic mock brain; Godot owns snapshot construction, protocol parsing, action validation/execution, request lifecycle, and fallback. Phase A does not connect a real LLM and does not alter the current combat NPCs in the main scene.

**Tech Stack:** Godot 4.7/GDScript, Node.js 22, TypeScript 5.8.3, Vitest 3.2.1, Ajv 8.17.1, Node built-in HTTP server.

**Configuration migration note (2026-08-26):** This historical Phase A plan predates the real role-Agent runtime. Current service and Godot settings are read only from the ignored JSON files documented in `services/agent-service/README.md`; the old process-level configuration described during Phase A is superseded.

## Global Constraints

- Protocol version is exactly `1` and every `POST` request carries an idempotency key.
- Godot remains authoritative for movement, collision, inventory, economy, quests, relationships, and save data.
- Phase A supports only `move_to`, `face_actor`, `speak`, `work`, and `wait` actions.
- The service only proposes actions; it never mutates Godot state.
- A stale `world_revision`, duplicate `decision_id`, unknown action, invalid parameter, or mismatched `npc_id` must not execute.
- Autonomous requests time out after `3.0` seconds and enter deterministic fallback.
- Automated tests never require a real LLM, provider API key, or public network connection.
- Do not reference `/Users/huanggui/workspace/loom` from production code or package metadata.
- Do not attach Phase A controllers to the current hostile NPCs in `scenes/main.tscn`; use the integration fixture until the peaceful Villager rewrite begins.

---

### Task 1: TypeScript service scaffold and protocol schemas

**Files:**
- Create: `services/agent-service/package.json`
- Create: `services/agent-service/tsconfig.json`
- Create: `services/agent-service/src/protocol/types.ts`
- Create: `services/agent-service/src/protocol/schemas.ts`
- Create: `services/agent-service/tests/protocol.test.ts`
- Create: `shared/agent_protocol/v1/fixtures/decision-request.json`
- Create: `shared/agent_protocol/v1/fixtures/decision-response.json`
- Create: `shared/agent_protocol/v1/fixtures/outcome-request.json`

**Interfaces:**
- Produces: `DecisionRequest`, `DecisionResponse`, `AgentAction`, `OutcomeRequest`, and `ActionOutcome` TypeScript types.
- Produces: `validateDecisionRequest(value)` and `validateOutcomeRequest(value)` type guards.
- Produces: shared JSON fixtures consumed by later Godot and HTTP tests.

- [ ] **Step 1: Write the failing protocol test**

Create `tests/protocol.test.ts` with tests that load all three fixtures, accept the valid requests, and reject a decision request with `protocol_version: 2`, an empty `request_id`, or a missing `snapshot`:

```ts
import { readFileSync } from "node:fs";
import { resolve } from "node:path";
import { describe, expect, it } from "vitest";
import { validateDecisionRequest, validateOutcomeRequest } from "../src/protocol/schemas.js";

const fixture = (name: string): unknown =>
  JSON.parse(readFileSync(resolve(process.cwd(), "../../shared/agent_protocol/v1/fixtures", name), "utf8"));

describe("agent protocol v1", () => {
  it("accepts shared request fixtures", () => {
    expect(validateDecisionRequest(fixture("decision-request.json")).ok).toBe(true);
    expect(validateOutcomeRequest(fixture("outcome-request.json")).ok).toBe(true);
  });

  it.each([
    { protocol_version: 2 },
    { request_id: "" },
    { snapshot: undefined },
  ])("rejects invalid decision request override %j", (override) => {
    const request = { ...(fixture("decision-request.json") as object), ...override };
    expect(validateDecisionRequest(request).ok).toBe(false);
  });
});
```

- [ ] **Step 2: Run the test to verify RED**

Run:

```bash
npm --prefix services/agent-service install
npm --prefix services/agent-service test -- tests/protocol.test.ts
```

Expected: FAIL because `package.json` and protocol modules do not exist.

- [ ] **Step 3: Add the service scaffold and exact protocol types**

Use `type: module`, scripts `build`, `typecheck`, `test`, and `start`; pin `ajv@8.17.1`, `typescript@5.8.3`, `vitest@3.2.1`, and `@types/node@22.15.29`. Configure strict NodeNext TypeScript with output in `dist/`.

Define these closed contracts in `types.ts`:

```ts
export const PROTOCOL_VERSION = 1 as const;
export type ActionType = "move_to" | "face_actor" | "speak" | "work" | "wait";

export interface AgentAction {
  readonly action_id: string;
  readonly type: ActionType;
  readonly params: Readonly<Record<string, unknown>>;
}

export interface DecisionRequest {
  readonly protocol_version: 1;
  readonly request_id: string;
  readonly save_id: string;
  readonly npc_id: string;
  readonly world_revision: number;
  readonly reason: string;
  readonly snapshot: Readonly<Record<string, unknown>>;
}

export interface DecisionResponse {
  readonly protocol_version: 1;
  readonly decision_id: string;
  readonly request_id: string;
  readonly npc_id: string;
  readonly world_revision: number;
  readonly trace_id: string;
  readonly actions: readonly AgentAction[];
  readonly next_think_after_ms: number;
}

export type OutcomeStatus = "accepted" | "rejected" | "completed" | "failed";
export interface ActionOutcome {
  readonly action_id: string;
  readonly status: OutcomeStatus;
  readonly reason?: string;
}

export interface OutcomeRequest {
  readonly protocol_version: 1;
  readonly outcome_id: string;
  readonly save_id: string;
  readonly npc_id: string;
  readonly decision_id: string;
  readonly outcomes: readonly ActionOutcome[];
}
```

In `schemas.ts`, compile Ajv schemas once and return `{ ok: true, value }` or `{ ok: false, errors }`. Set `additionalProperties: false` on the request envelope and allow arbitrary JSON-compatible fields only inside `snapshot` and action `params`.

Create fixtures using `save_id: "test-save"`, `npc_id: "villager-test"`, `world_revision: 7`, and deterministic IDs. The decision response must contain one `speak` action with text `"早上好。"`; the outcome fixture uses `outcome_id: "test-request-outcome-1"`.

- [ ] **Step 4: Run protocol tests and typecheck**

Run:

```bash
npm --prefix services/agent-service test -- tests/protocol.test.ts
npm --prefix services/agent-service run typecheck
```

Expected: protocol tests PASS and TypeScript exits `0`.

- [ ] **Step 5: Commit**

```bash
git add services/agent-service shared/agent_protocol/v1
git commit -m "feat: define NPC agent protocol v1"
```

### Task 2: Deterministic mock brain and idempotent decision store

**Files:**
- Create: `services/agent-service/src/agents/mock-brain.ts`
- Create: `services/agent-service/src/agents/decision-store.ts`
- Create: `services/agent-service/tests/mock-brain.test.ts`

**Interfaces:**
- Consumes: `DecisionRequest` and `DecisionResponse` from Task 1.
- Produces: `decide(request: DecisionRequest): DecisionResponse`.
- Produces: `DecisionStore.getOrCreate(request, factory)` and `DecisionStore.recordOutcomes(request)`.

- [ ] **Step 1: Write failing deterministic behavior and idempotency tests**

```ts
it("speaks when the player is perceived", () => {
  const response = decide(makeRequest({ perception: { nearby_player: true } }));
  expect(response.actions).toEqual([{ action_id: "test-request-action-1", type: "speak", params: { text: "早上好。" } }]);
});

it("waits when no player is perceived", () => {
  const response = decide(makeRequest({ perception: { nearby_player: false } }));
  expect(response.actions[0]).toMatchObject({ type: "wait", params: { duration_ms: 5000 } });
});

it("returns the same decision for a repeated request id", () => {
  const store = new DecisionStore();
  const first = store.getOrCreate(request, decide);
  const second = store.getOrCreate(request, decide);
  expect(second).toEqual(first);
  expect(store.size).toBe(1);
});
```

- [ ] **Step 2: Run the test to verify RED**

Run: `npm --prefix services/agent-service test -- tests/mock-brain.test.ts`

Expected: FAIL because the mock brain and store are missing.

- [ ] **Step 3: Implement the minimal mock brain**

Read `snapshot.perception.nearby_player` defensively. When true, return the fixture-compatible `speak`; otherwise return `wait`. Generate deterministic IDs from `request_id`, copy `npc_id` and `world_revision`, set `trace_id` to `${request_id}-trace`, and set `next_think_after_ms` to `8000`.

Implement `DecisionStore` with maps keyed by `save_id + ":" + request_id` and `save_id + ":" + decision_id`. Reject reuse of one request ID with a different NPC or world revision. Store outcome requests once per decision and expose them for tests.

- [ ] **Step 4: Run tests and typecheck**

Run:

```bash
npm --prefix services/agent-service test -- tests/mock-brain.test.ts
npm --prefix services/agent-service run typecheck
```

Expected: all mock brain tests PASS.

- [ ] **Step 5: Commit**

```bash
git add services/agent-service/src/agents services/agent-service/tests/mock-brain.test.ts
git commit -m "feat: add deterministic NPC mock brain"
```

### Task 3: Local HTTP Agent Service

**Files:**
- Create: `services/agent-service/src/api/app.ts`
- Create: `services/agent-service/src/server.ts`
- Create: `services/agent-service/tests/api.test.ts`

**Interfaces:**
- Consumes: protocol validators, `decide`, and `DecisionStore`.
- Produces: `createApp(store): (request, response) => void`.
- Produces: `GET /v1/health`, `POST /v1/npcs/:npc_id/decide`, and `POST /v1/decisions/:decision_id/outcomes`.

- [ ] **Step 1: Write failing HTTP tests**

Start `createServer(createApp(store))` on port `0` in `beforeEach` and close it in `afterEach`. Assert:

```ts
expect(await getJson("/v1/health")).toEqual({ status: "ok", protocol_version: 1 });

const decision = await postJson("/v1/npcs/villager-test/decide", validRequest, {
  Authorization: "Bearer test-session-token",
  "Idempotency-Key": validRequest.request_id,
  "X-Protocol-Version": "1",
});
expect(decision.status).toBe(200);
expect(decision.body.actions[0].type).toBe("speak");

expect((await postJson("/v1/npcs/other/decide", validRequest)).status).toBe(409);
expect((await postJson("/v1/npcs/villager-test/decide", { ...validRequest, snapshot: undefined })).status).toBe(400);
expect((await postJson("/v1/decisions/test-request-decision/outcomes", validOutcome, {
  Authorization: "Bearer test-session-token",
  "Idempotency-Key": validOutcome.outcome_id,
  "X-Protocol-Version": "1",
})).status).toBe(202);
```

- [ ] **Step 2: Run the API test to verify RED**

Run: `npm --prefix services/agent-service test -- tests/api.test.ts`

Expected: FAIL because the HTTP app is missing.

- [ ] **Step 3: Implement HTTP parsing and error envelopes**

Use only `node:http`. Limit JSON request bodies to `64 KiB`. Return JSON with `Content-Type: application/json`; use this error shape:

```ts
interface ApiErrorBody {
  readonly error: {
    readonly code: "BAD_REQUEST" | "UNAUTHORIZED" | "CONFLICT" | "NOT_FOUND" | "PAYLOAD_TOO_LARGE";
    readonly message: string;
  };
}
```

The Phase A prototype required an `Authorization: Bearer <token>` header; this historical mock-service requirement is not part of the current role-Agent service. Require `X-Protocol-Version: 1`; decision `Idempotency-Key` equals `request_id`, while outcome `Idempotency-Key` equals `outcome_id`. Require the path NPC/decision ID to equal the body ID. Return `401` for missing/invalid authorization, `400` for schema/header errors, `409` for identity conflicts, `404` for unknown routes, `413` over the body limit, `200` for decisions, and `202` for outcomes. Current bind settings come from the local service JSON configuration, with loopback host `127.0.0.1` and port `8787` as defaults.

- [ ] **Step 4: Run all service tests and build**

Run:

```bash
npm --prefix services/agent-service test
npm --prefix services/agent-service run build
```

Expected: all Vitest tests PASS and `dist/server.js` exists.

- [ ] **Step 5: Commit**

```bash
git add services/agent-service/src/api services/agent-service/src/server.ts services/agent-service/tests/api.test.ts
git commit -m "feat: expose local NPC agent HTTP service"
```

### Task 4: Godot protocol parser and shared fixture contract

**Files:**
- Create: `scripts/agents/agent_protocol.gd`
- Create: `tests/test_agent_protocol.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Consumes: `shared/agent_protocol/v1/fixtures/decision-response.json`.
- Produces: `AgentProtocol.parse_decision(body: Dictionary) -> Dictionary` returning `{ok, value}` or `{ok, error}`.
- Produces: `AgentProtocol.make_outcome_request(outcome_id, save_id, npc_id, decision_id, outcomes) -> Dictionary`.

- [ ] **Step 1: Write failing fixture and malformed-response tests**

```gdscript
const AgentProtocolScript = preload("res://scripts/agents/agent_protocol.gd")

func run(assertions) -> void:
	var fixture_text := FileAccess.get_file_as_string("res://shared/agent_protocol/v1/fixtures/decision-response.json")
	var parsed = AgentProtocolScript.parse_decision(JSON.parse_string(fixture_text))
	assertions.truthy(parsed.ok, "Godot accepts protocol v1 decision fixture")
	assertions.equal(parsed.value.actions[0].type, "speak", "Godot preserves action type")
	assertions.truthy(not AgentProtocolScript.parse_decision({"protocol_version": 2}).ok, "Godot rejects unknown protocol")
	var invalid_action := parsed.value.duplicate(true)
	invalid_action.actions[0].type = "change_gold"
	assertions.truthy(not AgentProtocolScript.parse_decision(invalid_action).ok, "Godot rejects unknown actions")
```

Register the test in `tests/run_tests.gd`.

- [ ] **Step 2: Run Godot tests to verify RED**

Run: `/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd`

Expected: preload failure because `agent_protocol.gd` is missing.

- [ ] **Step 3: Implement strict envelope and action parsing**

Validate exact required keys and types. Reject empty IDs, negative revisions, more than 8 actions, unknown action types, duplicate action IDs, and missing `params`. Validate parameters as follows:

```gdscript
const ACTION_KEYS := {
	"move_to": ["x", "z"],
	"face_actor": ["actor_id"],
	"speak": ["text"],
	"work": ["work_id"],
	"wait": ["duration_ms"],
}
```

Require finite numeric `x/z`, non-empty string IDs, `speak.text` length `1..280`, and integer `duration_ms` in `100..60000`. `make_outcome_request` always emits protocol version `1`, includes a non-empty `outcome_id`, and copies only `action_id`, `status`, and optional `reason`.

- [ ] **Step 4: Run Godot tests to verify GREEN**

Run the full Godot test command. Expected: exit `0` with all checks passing.

- [ ] **Step 5: Commit**

```bash
git add scripts/agents/agent_protocol.gd tests/test_agent_protocol.gd tests/run_tests.gd
git commit -m "feat: validate NPC agent protocol in Godot"
```

### Task 5: Filtered world snapshots

**Files:**
- Create: `scripts/agents/world_snapshot_builder.gd`
- Create: `tests/test_world_snapshot_builder.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `WorldSnapshotBuilder.build(npc, world_revision, game_context, perceived_actors, recent_events) -> Dictionary`.
- Produces snapshots containing only `game_time`, `self`, `perception`, and `recent_events`.

- [ ] **Step 1: Write failing perception-filter tests**

Create fixture Nodes with metadata `agent_id`, `display_name`, `visible_action`, and `private_goal`. Assert the snapshot includes public actor fields but does not contain `private_goal`, script paths, node paths, object instance IDs, or raw Nodes. Assert actors farther than `12.0` horizontal units and events without the NPC in `audience` are excluded.

```gdscript
assertions.equal(snapshot.perception.nearby_actors.size(), 1, "snapshot includes nearby actor")
assertions.truthy(not snapshot.perception.nearby_actors[0].has("private_goal"), "snapshot hides private goals")
assertions.equal(snapshot.recent_events.size(), 1, "snapshot filters event audience")
assertions.equal(snapshot.world_revision, 7, "snapshot preserves world revision")
```

- [ ] **Step 2: Run tests to verify RED**

Run the full Godot test command. Expected: missing `world_snapshot_builder.gd`.

- [ ] **Step 3: Implement deterministic snapshot construction**

Sort perceived actors by `agent_id`, cap them at 16, cap events at the most recent 24, and convert positions to `{x, y, z}` dictionaries rounded to three decimals. Copy only allowlisted game context keys: `season`, `day`, `hour`, `weather`, and `active_quest_ids`. Use horizontal distance and the exact `12.0` radius.

- [ ] **Step 4: Run tests to verify GREEN**

Run the full Godot test command. Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/agents/world_snapshot_builder.gd tests/test_world_snapshot_builder.gd tests/run_tests.gd
git commit -m "feat: build filtered NPC world snapshots"
```

### Task 6: Godot action validator and executor

**Files:**
- Create: `scripts/agents/agent_action_validator.gd`
- Create: `scripts/agents/agent_action_executor.gd`
- Create: `tests/fixtures/agent_actor.gd`
- Create: `tests/test_agent_action_execution.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `AgentActionValidator.validate(decision, expected_npc_id, current_revision, allowed_actions, seen_decisions) -> Dictionary`.
- Produces: `AgentActionExecutor.execute(actor, action) -> Dictionary` with one outcome.
- Actor contract: `set_agent_destination(Vector3)`, `face_agent_actor(String)`, `perform_agent_work(String)`, and emitted speech signal.

- [ ] **Step 1: Write failing authorization and execution tests**

Cover matching decisions, stale revisions, mismatched NPCs, repeated decision IDs, and unauthorized action types. Execute all five Phase A actions against `AgentActor` and assert exact outcomes:

```gdscript
assertions.equal(executor.execute(actor, speak_action).status, "completed", "speak completes")
assertions.equal(actor.last_speech, "早上好。", "speak reaches actor")
assertions.equal(executor.execute(actor, move_action).status, "accepted", "move starts asynchronously")
assertions.equal(actor.destination, Vector3(2.0, 0.0, -3.0), "move destination is applied")
assertions.equal(executor.execute(actor, {"action_id": "x", "type": "change_gold", "params": {}}).status, "rejected", "unknown action is rejected")
```

- [ ] **Step 2: Run tests to verify RED**

Run the full Godot test command. Expected: missing validator/executor scripts.

- [ ] **Step 3: Implement validation and execution**

The validator returns `{ok: false, reason: "stale_world_revision"}` and similarly stable snake-case reasons for every rejection. It must not mutate `seen_decisions` until the complete envelope passes. The executor never accesses global singletons; it calls only the actor contract and returns `accepted` for `move_to/work/wait`, `completed` for `face_actor/speak`, and `rejected` with `unsupported_action` otherwise.

The fixture actor stores every call in fields so tests can prove the executor has no hidden world mutation.

- [ ] **Step 4: Run tests to verify GREEN**

Run the full Godot test command. Expected: all checks pass.

- [ ] **Step 5: Commit**

```bash
git add scripts/agents/agent_action_validator.gd scripts/agents/agent_action_executor.gd tests/fixtures/agent_actor.gd tests/test_agent_action_execution.gd tests/run_tests.gd
git commit -m "feat: validate and execute NPC agent actions"
```

### Task 7: AgentGateway, controller lifecycle, and fallback

**Files:**
- Create: `scripts/agents/agent_gateway.gd`
- Create: `scripts/agents/fallback_villager_brain.gd`
- Create: `scripts/agents/npc_agent_controller.gd`
- Create: `tests/test_npc_agent_controller.gd`
- Modify: `tests/run_tests.gd`

**Interfaces:**
- Produces: `AgentGateway.request_decision(request, callback) -> void` and `report_outcomes(request, callback) -> void`.
- Produces: `FallbackVillagerBrain.decision_for(npc_id, revision, reason) -> Dictionary`.
- Produces: `NpcAgentController.configure(actor, gateway, save_id, npc_id, allowed_actions) -> void` and `think(snapshot, reason) -> void`.

- [ ] **Step 1: Write failing lifecycle tests with a fake gateway**

Test success, failure, timeout, stale response, duplicate in-flight request, and outcome reporting. The fake gateway captures requests and invokes supplied callbacks. Assert:

```gdscript
controller.think(snapshot, "nearby_player")
assertions.equal(fake_gateway.requests.size(), 1, "controller sends one request")
controller.think(snapshot, "duplicate_event")
assertions.equal(fake_gateway.requests.size(), 1, "controller serializes NPC requests")
fake_gateway.succeed(shared_decision)
assertions.equal(actor.last_speech, "早上好。", "controller executes valid decision")
assertions.equal(fake_gateway.outcome_requests.size(), 1, "controller reports outcomes")
fake_gateway.fail("timeout")
assertions.equal(controller.last_mode, "fallback", "timeout enters fallback")
```

- [ ] **Step 2: Run tests to verify RED**

Run the full Godot test command. Expected: missing lifecycle scripts.

- [ ] **Step 3: Implement gateway and controller**

`AgentGateway` creates one `HTTPRequest` child per call, sets a `3.0` second timeout, sends JSON with `Content-Type`, `Authorization`, `Idempotency-Key`, and `X-Protocol-Version`, and frees the request node after completion. Treat non-2xx, timeout, transport failure, and invalid JSON as failures with stable reasons.

`NpcAgentController` generates monotonically increasing request IDs per NPC, ignores callbacks that do not match the active request, runs protocol and action validation before execution, reports all action outcomes, remembers successful decision IDs, and clears the active request exactly once.

`FallbackVillagerBrain` returns a local `wait` action for autonomous failure and a local `speak` action with `"我现在有点忙，晚些再聊吧。"` for dialogue failure. It never performs HTTP.

- [ ] **Step 4: Run tests to verify GREEN**

Run the full Godot test command. Expected: all checks pass with no leaked HTTPRequest nodes.

- [ ] **Step 5: Commit**

```bash
git add scripts/agents tests/test_npc_agent_controller.gd tests/run_tests.gd
git commit -m "feat: orchestrate NPC agent requests with fallback"
```

### Task 8: Local end-to-end contract test and operator documentation

**Files:**
- Create: `tests/agent_service_integration.gd`
- Create: `services/agent-service/README.md`
- Modify: `.gitignore`

**Interfaces:**
- Consumes: compiled local Agent Service and shared fixtures.
- Produces: one command sequence proving health, decision, execution-compatible response, outcome acceptance, and fallback-safe shutdown.

- [ ] **Step 1: Write the failing Godot HTTP integration script**

Implement a `SceneTree` script that creates `HTTPRequest`, posts the shared decision request to `http://127.0.0.1:8787/v1/npcs/villager-test/decide`, parses the response through `AgentProtocol`, asserts the `speak` action, posts a completed outcome, prints `PASS: agent service integration`, and exits `0`. Any timeout, status mismatch, or parse failure must call `push_error` and exit `1`.

- [ ] **Step 2: Run the integration test before starting the service**

Run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/agent_service_integration.gd
```

Expected: exit `1` with a connection failure, proving the test exercises the network boundary.

- [ ] **Step 3: Document and ignore generated service output**

Add `services/agent-service/node_modules/` and `services/agent-service/dist/` to `.gitignore`. Document exact setup, start, test, health check, local JSON settings, protocol fixture paths, and the statement that Phase A is a deterministic mock and does not use an LLM key.

- [ ] **Step 4: Run the complete local vertical slice**

Run the service in one terminal:

```bash
npm --prefix services/agent-service install
npm --prefix services/agent-service run build
npm --prefix services/agent-service start
```

Then run:

```bash
curl --fail http://127.0.0.1:8787/v1/health
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/agent_service_integration.gd
npm --prefix services/agent-service test
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 120
```

Expected: health returns protocol version `1`, integration prints `PASS: agent service integration`, Vitest passes, Godot tests pass, and the main scene exits without errors.

- [ ] **Step 5: Stop the local service and verify fallback remains independent**

Stop the Node process, rerun the controller unit test suite, and confirm it still passes because failure behavior uses the fake gateway and deterministic fallback rather than a live service.

- [ ] **Step 6: Commit**

```bash
git add .gitignore tests/agent_service_integration.gd services/agent-service/README.md
git commit -m "test: verify local NPC agent service integration"
```

## Phase A Completion Gate

Before planning Phase B, verify all of the following on the final commit:

```bash
npm --prefix services/agent-service run typecheck
npm --prefix services/agent-service test
npm --prefix services/agent-service run build
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --script res://tests/run_tests.gd
/Applications/Godot.app/Contents/MacOS/Godot --headless --path /Users/huanggui/UnrealEngine/villa --quit-after 120
```

Then run the service-backed integration test once. Phase B may begin only when the deterministic fallback also passes with the service stopped.
