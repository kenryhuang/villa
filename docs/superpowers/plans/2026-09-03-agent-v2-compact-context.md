# Agent v2 Compact Context Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove legacy duplicated request fields and send a deterministic role-specific market summary to the model while preserving full market detail for local read tools.

**Architecture:** Godot owns the authoritative market and builds both a compact prompt summary and an immutable full lookup map. The v2 request carries both, but TypeScript removes the full lookup map when constructing the initial Provider message; local read tools retain access to it. The protocol rejects legacy fields rather than supporting two request shapes.

**Tech Stack:** Godot 4.7 GDScript, Node.js 24 TypeScript, Node test runner, JSON protocol fixtures.

---

### Task 1: Enforce the pure v2 request envelope

**Files:**
- Modify: `scripts/ai_agent/agent_protocol.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `services/agent-service/src/protocol.ts`
- Modify: `shared/agent_protocol/v2/decision-request.json`
- Modify: `services/agent-service/tests/protocol.test.ts`
- Modify: `tests/test_agent_main_integration.gd`
- Modify: `tests/agent_service_integration.gd`

- [x] **Step 1: Write failing protocol tests**

Add assertions that the shared request has no `snapshot` or `event_delta`, that either legacy field returns `legacy_request_fields`, and that `market_summary` is required.

```ts
const parsed = parseDecisionRequest({...request, snapshot: {}});
assert.deepEqual(parsed, {ok: false, error: "legacy_request_fields"});
assert.equal(parseDecisionRequest({...request, market_summary: undefined}).ok, false);
```

In the Godot integration assertion, require:

```gdscript
assertions.truthy(not initial_request.has("snapshot"), "v2 request omits legacy snapshot")
assertions.truthy(not initial_request.has("event_delta"), "v2 request omits legacy event delta")
```

- [x] **Step 2: Run tests and verify RED**

Run:

```powershell
node --experimental-strip-types --test tests/protocol.test.ts
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: TypeScript fails because legacy fields are accepted and `market_summary` is not required; Godot fails because the builder still emits both old fields.

- [x] **Step 3: Remove the legacy parameters and fields**

Change the Godot builder signature to:

```gdscript
static func make_decision_request(
	request_id: String, session_id: String, session_epoch: int,
	agent_id: String, trigger: String, game_minute: int,
	world_revision: int, dialogue_input: String = "", projection: Dictionary = {}
) -> Dictionary:
```

Do not insert `snapshot` or `event_delta`. Add `market_summary` to the copied projection fields. Update Runtime and connected-test call sites.

Remove both fields from `DecisionRequest` in TypeScript. Before normal field validation, reject their presence:

```ts
if (Object.hasOwn(value, "snapshot") || Object.hasOwn(value, "event_delta")) {
  return failure("legacy_request_fields");
}
```

Require `market_summary` to be a record and update the shared request fixture.

- [x] **Step 4: Run protocol and Agent tests and verify GREEN**

Run the two commands from Step 2. Expected: both pass.

### Task 2: Build deterministic role-specific market summaries

**Files:**
- Create: `scripts/ai_agent/agent_market_summary.gd`
- Create: `tests/test_agent_market_summary.gd`
- Modify: `tests/run_agent_system_tests.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`

- [x] **Step 1: Write failing summary tests**

Cover farmer, merchant, explorer, role change, stable ordering, empty market, zero target/base values, and signal caps. Use a compact fixture with seed, crop, fish, material, rare and supply items.

```gdscript
var farmer := builder.build("farmer", 480, {"inventory": {"carrot_seed": 2}}, [], market, catalog)
assertions.equal(farmer.role_id, "farmer", "farmer summary identifies active role")
assertions.truthy(_signal_ids(farmer).has("carrot_seed"), "farmer sees owned seed")
assertions.truthy(farmer.signals.size() <= 12, "farmer summary is capped")
```

- [x] **Step 2: Run Agent tests and verify RED**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: preload fails because `agent_market_summary.gd` does not exist.

- [x] **Step 3: Implement the summary builder**

Create a stateless `RefCounted` with:

```gdscript
func build(
	role_id: String,
	game_minute: int,
	actor_state: Dictionary,
	farm: Array,
	market: Dictionary,
	catalog: Dictionary
) -> Dictionary:
```

Calculate integer `stock_ratio_bps` and `price_change_bps`, attach deterministic reason codes, rank by role relevance then anomaly magnitude then `item_id`, deduplicate, and cap farmer/merchant/explorer signals at 12/20/10. Return schema version, role, generation minute, overview counts and signals.

- [x] **Step 4: Integrate summary construction into Runtime**

Build a catalog keyed by market item ID from `GameData.get_market_items()`. After constructing the authoritative full market map, set:

```gdscript
projected.market_summary = market_summary.build(
	str(capabilities.role_id), game_minute, state.to_dict(), farm_snapshot,
	market_snapshot, market_catalog
)
```

Keep `projected.market_view = market_snapshot` for local tool reads.

- [x] **Step 5: Run Agent tests and verify GREEN**

Run the command from Step 2. Expected: all checks pass.

### Task 3: Keep full market data out of the Provider prompt

**Files:**
- Modify: `services/agent-service/src/protocol.ts`
- Modify: `services/agent-service/src/agents.ts`
- Modify: `services/agent-service/src/provider.ts`
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `services/agent-service/tests/agents.test.ts`
- Modify: `services/agent-service/tests/provider_stream.test.ts`

- [x] **Step 1: Write failing Provider tests**

Capture the first Provider request and assert the compact summary is present while the full map and a sentinel market detail are absent:

```ts
assert.deepEqual(sentContext.market_summary, request.market_summary);
assert.equal(Object.hasOwn(sentContext, "market_view"), false);
assert.doesNotMatch(JSON.stringify(firstProviderBody), /FULL_MARKET_SENTINEL/);
```

Also assert `inspect_market_item` can still return the sentinel detail from `AgentContext.market_view`.

- [x] **Step 2: Run Provider tests and verify RED**

Run:

```powershell
node --experimental-strip-types --test tests/provider.test.ts tests/agents.test.ts tests/provider_stream.test.ts
```

Expected: initial Provider body still contains `market_view`.

- [x] **Step 3: Separate prompt context from tool context**

Add `market_summary` to `AgentContext`. Build the initial prompt copy explicitly:

```ts
const {market_view: _marketView, ...promptContext} = context;
const userContent = isDialogue
  ? {context: promptContext, dialogue_input: request.dialogue_input ?? ""}
  : promptContext;
```

Continue passing the original full `context` to `executeReadTool`, so all market reads remain exact and immutable for the decision.

- [x] **Step 4: Run Provider tests and verify GREEN**

Run the command from Step 2. Expected: all pass.

### Task 4: Validate payload size and connected behavior

**Files:**
- Modify: `services/agent-service/tests/app.test.ts`
- Modify: `tests/agent_runtime_service_integration.gd`

- [x] **Step 1: Update payload regression checks**

Update the service fixture to the pure v2 shape. In the Runtime connected test, build one real request before dispatch and fail if legacy fields exist or its serialized size is at least 131072 bytes:

```gdscript
var request: Dictionary = runtime.call("_build_request", "farmer_ahe", "dialogue", 0, "size check")
if request.has("snapshot") or request.has("event_delta"):
	_fail("legacy_request_fields")
if JSON.stringify(request).to_utf8_buffer().size() >= 131072:
	_fail("runtime_request_too_large")
runtime.call("_handle_stream_failure", "farmer_ahe", str(request.request_id), "measurement")
```

- [x] **Step 2: Run focused local suites**

Run:

```powershell
npm test
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: TypeScript suite and Agent suite both pass.

- [x] **Step 3: Restart the local Agent Service**

Verify the exact PID owning `127.0.0.1:8787`, stop only that PID, and start latest source with the configured local JSON and hidden window. Keep stdout/stderr under `D:\UnityProject\villa\tmp`.

- [x] **Step 4: Run real connected acceptance tests**

Run:

```powershell
godot_console --headless --path . --script res://tests/agent_service_integration.gd
godot_console --headless --path . --script res://tests/agent_runtime_service_integration.gd
```

Expected: both print PASS and exit 0; service stderr remains empty.

- [x] **Step 5: Inspect final diff**

Run `git diff --check` and `git status --short`. Confirm no local Provider key or generated database/log file is staged.
