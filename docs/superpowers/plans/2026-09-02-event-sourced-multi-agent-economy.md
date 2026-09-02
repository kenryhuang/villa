# Event-Sourced Multi-Agent Economy Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give every NPC Agent shared public-world awareness, per-actor recent activity, private event queues, real negotiation/cooperation tools, dynamic roles, and bounded market impact backed by a replayable Godot event log.

**Architecture:** Add an event-sourced Agent bounded context inside Godot without converting the rest of the game to event sourcing. World facts flow through a bridge into an append-only event store; deterministic projections build public world, actor activity, private inbox, interactions, agreements, relationships, roles, and market pressure. Existing inventory, NPC economy, farming, and market systems remain domain authorities and are mutated only through transactional adapters coordinated by Agent commands.

**Tech Stack:** Godot 4.7/GDScript, Node 24/TypeScript, OpenAI-compatible streaming chat completions, JSON save data, SQLite Agent memory, existing custom Godot test runners.

---

## File map

New focused Godot units:

- `scripts/ai_agent/agent_world_event_store.gd`: immutable event batches, global sequence, aggregate versions, idempotency, replay-safe serialization.
- `scripts/ai_agent/agent_world_projector.gd`: public world, actor activity, private delivery cursors, role, relationship, interaction, agreement, and market-pressure projections.
- `scripts/ai_agent/agent_world_fact_bridge.gd`: converts committed Season/Market/world signals into deduplicated public facts.
- `scripts/ai_agent/agent_context_projection.gd`: builds visibility-filtered request snapshots and freezes/acknowledges per-Agent deltas.
- `scripts/ai_agent/agent_interaction_system.gd`: messages, offers, reservations, counteroffers, expiry, and atomic settlement.
- `scripts/ai_agent/agent_agreement_system.gd`: cooperation templates, negotiation, commitments, contribution verification, and settlement.
- `scripts/ai_agent/agent_role_system.gd`: current role, eligibility checks, cooldowns, and capability changes.
- `scripts/data/agent_world_event.gd`: strict event-envelope normalization helpers.
- `data/agents/cooperation_templates.json`: deterministic initial cooperation definitions.
- `data/agents/role_transitions.json`: deterministic role eligibility and cost rules.
- `tests/test_agent_event_store.gd`, `tests/test_agent_perception_projection.gd`, `tests/test_agent_interactions.gd`, `tests/test_agent_agreements.gd`, `tests/test_agent_roles.gd`: focused TDD coverage.

Existing integration points:

- `scripts/ai_agent/agent_runtime.gd`: construct the new bounded context, route facts, build requests, acknowledge deltas, save/load.
- `scripts/ai_agent/agent_action_executor_router.gd`: route new commands to focused domain systems.
- `scripts/ai_agent/agent_action_validator.gd`, `scripts/ai_agent/agent_protocol.gd`, `scripts/ai_agent/agent_registry.gd`: dynamic command authorization and expanded v2 context.
- `scripts/systems/market_system.gd`: bounded external pressure input used by normal price settlement.
- `scripts/systems/npc_economy_system.gd`: reservation-aware available balances and atomic peer transfer adapter.
- `scripts/core/event_bus.gd`: public world/interaction signals.
- `scripts/core/save_manager.gd`, `scripts/main.gd`: dependency wiring and Agent Runtime migration.
- `scripts/ui/dialogue_ui.gd` and `scenes/ui/dialogue_ui.tscn`: Player trade/cooperation cards and explicit confirmation.
- `services/agent-service/src/agents.ts`, `protocol.ts`, `provider.ts`, `provider_stream.ts`, `tool_contracts.ts`: dynamic role context, local read tools, and dialogue-safe commands.
- `services/agent-service/tests/*.test.ts`: service protocol and provider-loop regressions.
- `tests/run_agent_system_tests.gd`: include every new focused suite.

### Task 1: Establish baseline and append-only event store

**Files:**
- Create: `scripts/data/agent_world_event.gd`
- Create: `scripts/ai_agent/agent_world_event_store.gd`
- Create: `tests/test_agent_event_store.gd`
- Modify: `tests/run_agent_system_tests.gd`

- [ ] **Step 1: Record the clean baseline**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
Push-Location services/agent-service; npm test; Pop-Location
```

Expected: existing Agent runner and all TypeScript tests pass before edits. Record exact counts in the validation log at Task 11.

- [ ] **Step 2: Write failing event-store tests**

Cover strict envelope fields, atomic two-event append, monotonic `global_sequence`, per-aggregate versioning, duplicate `idempotency_key`, failed-batch no-op, `to_dict/from_dict`, corrupted sequence rejection, and full replay ordering. Add the suite to `run_agent_system_tests.gd`:

```gdscript
const AgentEventStoreTest = preload("res://tests/test_agent_event_store.gd")
# in _run()
AgentEventStoreTest.new().run(assertions)
```

- [ ] **Step 3: Run the Agent suite and verify RED**

Run:

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
```

Expected: parse/preload failure because the new store does not exist.

- [ ] **Step 4: Implement strict event normalization and storage**

Provide this public surface:

```gdscript
func append_batch(events: Array[Dictionary], idempotency_key: String) -> Dictionary
func get_events_after(sequence: int) -> Array[Dictionary]
func get_aggregate_version(aggregate_type: String, aggregate_id: String) -> int
func get_idempotent_result(idempotency_key: String) -> Dictionary
func to_dict() -> Dictionary
func validate_dict(value: Dictionary) -> bool
func from_dict(value: Dictionary) -> bool
```

`append_batch` must normalize all events before mutation, assign contiguous sequences and aggregate versions on a candidate copy, and commit only when the whole batch validates. Return `{ok, events, last_sequence}` or a stable `{ok:false,error}`.

- [ ] **Step 5: Verify GREEN and commit**

Run the Agent suite, then:

```powershell
git add scripts/data/agent_world_event.gd scripts/ai_agent/agent_world_event_store.gd tests/test_agent_event_store.gd tests/run_agent_system_tests.gd
git commit -m "feat: add agent world event store"
```

### Task 2: Deterministic perception projections and independent inboxes

**Files:**
- Create: `scripts/ai_agent/agent_world_projector.gd`
- Create: `scripts/ai_agent/agent_context_projection.gd`
- Create: `tests/test_agent_perception_projection.gd`
- Modify: `tests/run_agent_system_tests.gd`
- Modify: `scripts/ai_agent/agent_perception_inbox.gd`

- [ ] **Step 1: Write failing projection tests**

Prove:

- `DayStarted`, `SeasonChanged`, `WeatherChanged`, environment and market public facts reach all three Agent inboxes;
- consuming one Agent's delta does not remove another Agent's copy;
- failed/cancelled requests do not advance `last_consumed_sequence`;
- acknowledging a valid response advances only that Agent;
- `known_actors` includes `current_public_state` and up to 12 visible recent events;
- participants/private events never leak to unrelated actors;
- global projection retains 64 and each actor retains 32 public events while the immutable store retains all;
- request context selects at most 24 global public events.

- [ ] **Step 2: Run RED**

Expected: missing projector/context APIs.

- [ ] **Step 3: Implement projector and frozen inbox batches**

Use explicit APIs:

```gdscript
func replay(events: Array[Dictionary]) -> bool
func apply_batch(events: Array[Dictionary]) -> bool
func public_world_state() -> Dictionary
func global_public_events(limit: int = 24) -> Array[Dictionary]
func known_actors(observer_id: String) -> Array[Dictionary]
func freeze_delta(agent_id: String, request_id: String) -> Array[Dictionary]
func acknowledge_delta(agent_id: String, request_id: String) -> bool
func release_delta(agent_id: String, request_id: String) -> bool
```

Replace destructive `drain()` use with freeze/acknowledge semantics. Visibility scopes are exactly `public`, `region`, `participants`, `private`, and `system`.

- [ ] **Step 4: Verify GREEN and commit**

```powershell
git add scripts/ai_agent/agent_world_projector.gd scripts/ai_agent/agent_context_projection.gd scripts/ai_agent/agent_perception_inbox.gd tests/test_agent_perception_projection.gd tests/run_agent_system_tests.gd
git commit -m "feat: project multi-agent public perception"
```

### Task 3: Bridge authoritative world facts and build complete Runtime context

**Files:**
- Create: `scripts/ai_agent/agent_world_fact_bridge.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `scripts/ai_agent/agent_protocol.gd`
- Modify: `scripts/core/event_bus.gd`
- Modify: `tests/test_agent_runtime.gd`
- Modify: `tests/test_agent_main_integration.gd`

- [ ] **Step 1: Write failing runtime tests**

Require every Agent request to include:

```text
public_world_state
global_public_events
known_actors
own_event_delta
market_view
```

Test day/season/market signals, stable fact deduplication, visibility, response acknowledgement, failure release, and correction facts after bridge publication failure.

- [ ] **Step 2: Run RED**

Expected: requests still use the old `snapshot + drain(agent_id)` shape and market events only target `lao_li`.

- [ ] **Step 3: Implement `WorldFactBridge` and Runtime integration**

The bridge subscribes only to committed EventBus signals and emits normalized events such as:

```gdscript
{
  "event_type": "SeasonChanged",
  "aggregate_type": "public_world",
  "aggregate_id": "season",
  "visibility": {"scope": "public", "actor_ids": []},
  "payload": {"season": season_id}
}
```

Remove the `lao_li`-only market routing. Build requests through `AgentContextProjection`; acknowledge on valid complete response, release on stream failure/cancel. Continue using protocol v2 and 0–3 final actions.

- [ ] **Step 4: Verify and commit**

Run the Agent suite and main startup smoke test, then commit:

```powershell
git add scripts/ai_agent/agent_world_fact_bridge.gd scripts/ai_agent/agent_runtime.gd scripts/ai_agent/agent_protocol.gd scripts/core/event_bus.gd tests/test_agent_runtime.gd tests/test_agent_main_integration.gd
git commit -m "feat: feed public world facts to every agent"
```

### Task 4: Dynamic role projection and authorization

**Files:**
- Create: `scripts/ai_agent/agent_role_system.gd`
- Create: `data/agents/role_transitions.json`
- Create: `tests/test_agent_roles.gd`
- Modify: `scripts/ai_agent/agent_registry.gd`
- Modify: `scripts/ai_agent/agent_action_validator.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `tests/run_agent_system_tests.gd`

- [ ] **Step 1: Write failing role tests**

Test a single active role, retained Soul/history/general tools, farmer/merchant/explorer eligibility, exact cost, cooldown, rejected audit event, successful `RoleChanged`, immediate goal/tool/schedule replacement, and rejection of a late old-role action with `role_capability_changed`.

- [ ] **Step 2: Run RED**

Expected: registry remains immutable and role transition APIs do not exist.

- [ ] **Step 3: Implement role rules and current capability lookup**

Expose:

```gdscript
func get_active_role(agent_id: String) -> String
func get_capabilities(agent_id: String) -> Dictionary
func propose_change(agent_id: String, target_role_id: String, motivation: String, game_minute: int, idempotency_key: String) -> Dictionary
func validate_dict(value: Dictionary) -> bool
func to_dict() -> Dictionary
func from_dict(value: Dictionary) -> bool
```

The validator must consult `AgentRoleSystem`, not static merged profile tools. Rules in JSON must name concrete required items, minimum gold, completed-event counts, region/building requirements, cost, and cooldown.

- [ ] **Step 4: Verify and commit**

```powershell
git add scripts/ai_agent/agent_role_system.gd data/agents/role_transitions.json scripts/ai_agent/agent_registry.gd scripts/ai_agent/agent_action_validator.gd scripts/ai_agent/agent_runtime.gd tests/test_agent_roles.gd tests/run_agent_system_tests.gd
git commit -m "feat: support event-sourced agent roles"
```

### Task 5: Agent Service dynamic context and local read-tool loop

**Files:**
- Modify: `services/agent-service/src/agents.ts`
- Modify: `services/agent-service/src/protocol.ts`
- Modify: `services/agent-service/src/provider.ts`
- Modify: `services/agent-service/src/provider_stream.ts`
- Modify: `services/agent-service/src/tool_contracts.ts`
- Modify: `services/agent-service/tests/agents.test.ts`
- Modify: `services/agent-service/tests/protocol.test.ts`
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `services/agent-service/tests/provider_stream.test.ts`

- [ ] **Step 1: Write failing TypeScript tests**

Require strict v2 parsing of the expanded projection, dynamic active role/goals, intersection of local and Godot tool lists, public/private event separation, read tools that cannot escape the supplied context, at most 6 read calls, 0–3 final commands, and at most one interaction command during dialogue.

- [ ] **Step 2: Run RED**

```powershell
Push-Location services/agent-service; npm test; Pop-Location
```

Expected: expanded context and read-loop assertions fail.

- [ ] **Step 3: Implement local reads and final-command separation**

Introduce distinct contracts:

```ts
type ReadToolName = "inspect_market_item" | "compare_market_items" |
  "inspect_known_actor" | "inspect_relationship" | "inspect_trade_offer" |
  "inspect_agreement" | "inspect_role_option" | "inspect_self_resources" |
  "inspect_farm_plots" | "inspect_crop_options" | "inspect_market_depth" |
  "inspect_price_history" | "inspect_region" | "inspect_known_discoveries";

type DecisionContext = {
  public_world_state: Record<string, unknown>;
  global_public_events: readonly Record<string, unknown>[];
  known_actors: readonly Record<string, unknown>[];
  own_event_delta: readonly Record<string, unknown>[];
};
```

Read results are computed locally from the immutable context and returned to the Provider for another turn. Only command tools enter the Godot `actions` array.

- [ ] **Step 4: Verify and commit**

```powershell
Push-Location services/agent-service; npm test; Pop-Location
git add services/agent-service/src services/agent-service/tests
git commit -m "feat: add dynamic agent context tools"
```

### Task 6: Messages, bilateral offers, reservations, and atomic settlement

**Files:**
- Create: `scripts/ai_agent/agent_interaction_system.gd`
- Create: `tests/test_agent_interactions.gd`
- Modify: `scripts/systems/npc_economy_system.gd`
- Modify: `scripts/ai_agent/agent_action_executor_router.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `scripts/core/event_bus.gd`
- Modify: `services/agent-service/src/tool_contracts.ts`
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `tests/run_agent_system_tests.gd`

- [ ] **Step 1: Write failing interaction tests**

Cover `send_message` versus regional public `speak`, untrusted text preservation, propose/accept/reject/cancel/counter/expire, proposer reservation, duplicate-spend prevention, counteroffer lock replacement, receiver asset recheck, NPC↔NPC atomic transfer, exact integer overflow guards, idempotency, and urgent receiver wakeup.

- [ ] **Step 2: Run RED**

Expected: `propose_trade` remains a no-op and no reservation API exists.

- [ ] **Step 3: Implement interaction aggregates**

Use:

```gdscript
func execute(command: Dictionary, game_minute: int) -> Dictionary
func expire_due(game_minute: int) -> Array[Dictionary]
func available_item(actor_id: String, item_id: String) -> int
func available_gold(actor_id: String) -> int
func get_offer(offer_id: String, observer_id: String) -> Dictionary
```

An offer locks only the proposer side. Accept stages both inventories/wallets and the event batch, then commits all or restores all. Player-targeted acceptance returns `player_confirmation_required` until submitted by the Player UI command path.

- [ ] **Step 4: Verify and commit**

Run Godot Agent and TypeScript suites, then:

```powershell
git add scripts/ai_agent/agent_interaction_system.gd scripts/systems/npc_economy_system.gd scripts/ai_agent/agent_action_executor_router.gd scripts/ai_agent/agent_runtime.gd scripts/core/event_bus.gd services/agent-service/src/tool_contracts.ts services/agent-service/tests/provider.test.ts tests/test_agent_interactions.gd tests/run_agent_system_tests.gd
git commit -m "feat: add agent negotiation and peer trading"
```

### Task 7: Bounded private-market pressure

**Files:**
- Modify: `scripts/ai_agent/agent_world_projector.gd`
- Modify: `scripts/systems/market_system.gd`
- Modify: `scripts/ai_agent/agent_interaction_system.gd`
- Modify: `tests/test_agent_interactions.gd`
- Modify: `tests/test_market_system.gd`

- [ ] **Step 1: Write failing pressure tests**

Prove public buy/sell behavior remains unchanged; private settlement leaves public stock unchanged; funded open buy/sell offers add pressure; close/expire removes open pressure; clearing above/below midpoint creates capped signed price-discovery pressure; per-offer, per-Agent, and per-day caps hold; normal settlement consumes pressure once.

- [ ] **Step 2: Run RED**

Run Agent and market suites. Expected: MarketSystem has no external pressure settlement API.

- [ ] **Step 3: Implement bounded pressure input**

Add to MarketSystem:

```gdscript
func set_agent_market_pressure(snapshot: Dictionary) -> bool
func get_agent_market_pressure() -> Dictionary
```

Apply a clamped factor inside existing price settlement, never assign price directly. Emit `MarketPressureSettled` after consumption.

- [ ] **Step 4: Verify and commit**

```powershell
git add scripts/ai_agent/agent_world_projector.gd scripts/systems/market_system.gd scripts/ai_agent/agent_interaction_system.gd tests/test_agent_interactions.gd tests/test_market_system.gd
git commit -m "feat: price private agent market signals"
```

### Task 8: Formal cooperation agreements

**Files:**
- Create: `scripts/ai_agent/agent_agreement_system.gd`
- Create: `data/agents/cooperation_templates.json`
- Create: `tests/test_agent_agreements.gd`
- Modify: `scripts/ai_agent/agent_action_executor_router.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `services/agent-service/src/tool_contracts.ts`
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `tests/run_agent_system_tests.gd`

- [ ] **Step 1: Define concrete initial templates and failing tests**

Add `joint_crop_supply`, `exploration_sample`, `material_procurement`, and `shared_construction`. Tests cover proposal/versioned counter, all-party acceptance, Player manual acceptance, resource commitment locks, action-linked contribution verification, deterministic milestones, deadline failure, cancellation policy, exact integer reward split, relationship effects, and atomic completion settlement.

- [ ] **Step 2: Run RED**

Expected: agreement APIs and command tools are missing.

- [ ] **Step 3: Implement agreement lifecycle**

Expose:

```gdscript
func execute(command: Dictionary, game_minute: int) -> Dictionary
func record_action_outcome(outcome: Dictionary, game_minute: int) -> Array[Dictionary]
func expire_due(game_minute: int) -> Array[Dictionary]
func get_agreement(agreement_id: String, observer_id: String) -> Dictionary
```

Templates, not LLM text, define required contribution types, milestone predicates, refund policy, deadline range, and reward rounding.

- [ ] **Step 4: Verify and commit**

```powershell
git add scripts/ai_agent/agent_agreement_system.gd data/agents/cooperation_templates.json scripts/ai_agent/agent_action_executor_router.gd scripts/ai_agent/agent_runtime.gd services/agent-service/src/tool_contracts.ts services/agent-service/tests/provider.test.ts tests/test_agent_agreements.gd tests/run_agent_system_tests.gd
git commit -m "feat: add agent cooperation agreements"
```

### Task 9: Player confirmation cards and dialogue command subset

**Files:**
- Modify: `scripts/ui/dialogue_ui.gd`
- Modify: `scenes/ui/dialogue_ui.tscn`
- Modify: `scripts/main.gd`
- Modify: `scripts/actors/npc.gd`
- Modify: `tests/test_agent_dialogue_ui.gd`
- Modify: `tests/test_visible_agent_npc_dialogue.gd`

- [ ] **Step 1: Write failing UI interaction tests**

Require fixed-size scrollable dialogue history plus pending trade/cooperation cards, exact current terms, expiry state, accept/reject/counter buttons, no asset mutation on text reply/close, explicit Player command on button click, and reopening the NPC dialogue with pending cards intact.

- [ ] **Step 2: Run RED**

Expected: dialogue panel has no structured interaction controls.

- [ ] **Step 3: Implement generic interaction cards**

Render projection data rather than Provider prose. Emit:

```gdscript
signal interaction_response_requested(
    agent_id: String,
    interaction_id: String,
    response: String,
    counter_terms: Dictionary
)
```

Main routes button actions to the Runtime Player-command entry point. Keep gameplay input blocked only while the dialogue is visible and restore it on every close path.

- [ ] **Step 4: Verify and commit**

```powershell
git add scripts/ui/dialogue_ui.gd scenes/ui/dialogue_ui.tscn scripts/main.gd scripts/actors/npc.gd tests/test_agent_dialogue_ui.gd tests/test_visible_agent_npc_dialogue.gd
git commit -m "feat: confirm agent interactions in dialogue"
```

### Task 10: Save migration, checkpoint replay, and Runtime composition

**Files:**
- Modify: `scripts/ai_agent/agent_runtime.gd`
- Modify: `scripts/core/save_manager.gd`
- Modify: `scripts/main.gd`
- Modify: `tests/test_agent_world_state.gd`
- Modify: `tests/test_agent_main_integration.gd`
- Modify: `tests/test_economy_save_integration.gd`

- [ ] **Step 1: Write failing save/replay tests**

Require next Runtime save version with event schema, next sequence, full event log, deterministic checkpoint, checkpoint sequence, per-Agent consumption cursors, and idempotency outcomes. Test atomic corrupt-log rejection, from-zero replay equivalence, checkpoint-plus-tail equivalence, pending locks/agreements/roles/pressure restore, and v2/v3 bootstrap migration without deleting world saves or SQLite memory.

- [ ] **Step 2: Run RED**

Run Agent and economy-save integration suites. Expected: new save fields/version absent; preserve the recorded unrelated aggregate baseline separately.

- [ ] **Step 3: Implement migration and composition**

`AgentRuntime.configure()` owns and wires store, projector, context, bridge, interactions, agreements, and roles. `to_dict()` writes the complete bounded context. `from_dict()` validates into temporary instances before swapping live state. Old saves produce one deterministic `AgentWorldBootstrapped` event from their current authoritative data.

- [ ] **Step 4: Verify and commit**

```powershell
git add scripts/ai_agent/agent_runtime.gd scripts/core/save_manager.gd scripts/main.gd tests/test_agent_world_state.gd tests/test_agent_main_integration.gd tests/test_economy_save_integration.gd
git commit -m "feat: persist event-sourced agent world"
```

### Task 11: Full integration verification and documentation

**Files:**
- Create: `docs/validation/agent-system-validation.md`
- Modify: `docs/superpowers/plans/2026-09-02-event-sourced-multi-agent-economy.md`

- [ ] **Step 1: Run focused and service regressions**

```powershell
godot_console --headless --path . --script res://tests/run_agent_system_tests.gd
godot_console --headless --path . --script res://tests/run_economy_system_tests.gd
godot_console --headless --path . --script res://tests/run_economy_save_integration_tests.gd
godot_console --headless --path . --script res://tests/run_main_gameplay_integration_tests.gd
Push-Location services/agent-service; npm test; Pop-Location
```

Expected: focused suites and service tests pass; aggregate suites introduce no failures beyond the recorded existing baselines.

- [ ] **Step 2: Verify parsing and startup**

```powershell
godot_console --headless --path . --editor --quit
godot_console --headless --path . --quit-after 3
git diff --check
```

Expected: zero exit codes and no new parse/startup errors. Delete only untracked `.gd.uid` files generated by the editor after a dry-run listing.

- [ ] **Step 3: Exercise the configured local service path**

Start the local TypeScript service from its existing local JSON configuration, issue a Godot-shaped streaming decision request containing public world events, known actors and a private delta, and verify a protocol-v2 response with 0–3 authorized commands. Do not log the configured API key.

- [ ] **Step 4: Record evidence and complete the plan**

Append exact commands/counts, migration behavior, known baselines and manual scenario results to `docs/validation/agent-system-validation.md`; mark every completed checkbox in this plan; run `git diff --check`; commit:

```powershell
git add docs/validation/agent-system-validation.md docs/superpowers/plans/2026-09-02-event-sourced-multi-agent-economy.md
git commit -m "docs: validate event-sourced multi-agent economy"
```

Do not merge or push unless the user asks separately.
