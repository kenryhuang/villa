# Agent Protocol v2 Multi-Action Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Upgrade the Agent stack to protocol v2, support zero to three ordered actions per decision, execute against current authoritative state without world-revision rejection or model retry, and erase all pre-v2 Agent databases and checkpoints once.

**Architecture:** TypeScript owns the v2 wire contract, Provider normalization, per-action IDs, and destructive SQLite migration. Godot strictly validates a v2 action batch, then executes its actions sequentially through the existing authoritative tool implementations; failures and in-progress results stop later actions while earlier commits remain.

**Tech Stack:** Node.js 24 TypeScript strip-types runner, OpenAI-compatible streaming Chat Completions, SQLite, Godot 4.7 GDScript, HTTP/SSE, repository-native test runners.

---

## File Structure

- Create `shared/agent_protocol/v2/*.json`: canonical v2 request, decision, and outcome fixtures.
- Modify `services/agent-service/src/protocol.ts`: v2 types and strict parsers.
- Modify `services/agent-service/src/provider_stream.ts`: normalize zero to three Provider calls into ordered actions.
- Modify `services/agent-service/src/provider.ts`: request zero to three tools.
- Modify `services/agent-service/src/memory.ts`: one-time full pre-v2 database reset.
- Modify `services/agent-service/src/server.ts`: coordinate checkpoint cleanup before listening.
- Modify `services/agent-service/src/app.ts`: v2 SSE/health, action-list memory, and v2 outcomes.
- Modify corresponding `services/agent-service/tests/*.test.ts` files.
- Modify `scripts/ai_agent/agent_protocol.gd`: v2 request and decision parsing.
- Modify `scripts/ai_agent/agent_action_validator.gd`: batch validation without revision equality.
- Modify `scripts/ai_agent/agent_action_executor_router.gd`: sequential batch execution and per-action outcomes.
- Modify `scripts/ai_agent/agent_runtime.gd`: publish/report every attempted outcome.
- Modify `scripts/ai_agent/agent_sse_parser.gd`: require v2 envelopes.
- Modify Agent Godot tests and connected acceptance runner.

### Task 1: Define the strict protocol v2 contract

**Files:**
- Create: `shared/agent_protocol/v2/decision-request.json`
- Create: `shared/agent_protocol/v2/action-intent.json`
- Create: `shared/agent_protocol/v2/action-outcome.json`
- Modify: `services/agent-service/tests/protocol.test.ts`
- Modify: `services/agent-service/src/protocol.ts`

- [ ] Write tests that load `shared/agent_protocol/v2`, accept `actions: []` and one-to-three valid actions, reject v1, reject four actions, reject duplicate `action_id` or `idempotency_key`, enforce `wait` exclusivity, and require `action_id` in outcomes.
- [ ] Run `npm test -- --test-name-pattern="protocol"` from `services/agent-service` and confirm RED because only v1 and a single action exist.
- [ ] Set `PROTOCOL_VERSION = 2`; define `ActionCommand` and `ActionIntent.actions`; make `parseActionIntent` validate exact batch bounds `0..3`, action authorization, unique IDs/keys, tool version, argument object, and exclusive `wait`. Make `parseActionOutcome` require `action_id`.
- [ ] Add canonical v2 fixture JSON. Do not modify or load the old v1 fixtures.
- [ ] Run `npm test -- --test-name-pattern="protocol"` and confirm GREEN.
- [ ] Commit with `git commit -m "feat: define Agent protocol v2"`.

The canonical TypeScript shape is:

```ts
export interface ActionCommand {
  action_id: string;
  idempotency_key: string;
  tool_name: string;
  tool_version: 1;
  arguments: Record<string, unknown>;
}

export interface ActionIntent {
  protocol_version: 2;
  decision_id: string;
  request_id: string;
  agent_id: string;
  expected_revision: number;
  actions: readonly ActionCommand[];
  speech?: string;
  decision_summary: string;
}
```

### Task 2: Normalize zero to three streamed Provider tool calls

**Files:**
- Modify: `services/agent-service/tests/provider_stream.test.ts`
- Modify: `services/agent-service/tests/provider.test.ts`
- Modify: `services/agent-service/src/provider_stream.ts`
- Modify: `services/agent-service/src/provider.ts`

- [ ] Update request fixtures to v2. Add RED tests for empty calls, ordered two/three calls with fragmented interleaved arguments, four-call rejection, invalid action rejection, wait exclusivity, and deterministic unique keys such as `v2:<request>:<index>:<action>`.
- [ ] Run `npm test -- --test-name-pattern="Provider|provider"` and confirm failures cite the single-tool requirement or old intent shape.
- [ ] Change `AgentStreamAssembler.finish()` to accept `0..3` sorted accumulators, validate every tool through `validToolArguments`, reject `wait` in a multi-action batch, and construct `actions`. Preserve raw Provider output and all streaming deltas.
- [ ] Change the Provider system prompt to permit zero to three ordered authorized tool calls and recommend placing travel/build last. Keep `tool_choice: "auto"`.
- [ ] Run the Provider tests and the full `npm test`; confirm GREEN.
- [ ] Commit with `git commit -m "feat: stream multi-action Agent decisions"`.

For each sorted Provider entry, generate:

```ts
const actionId = tool.id || `action-${index}`;
return {
  action_id: actionId,
  idempotency_key: `v2:${request.request_id}:${index}:${actionId}`,
  tool_name: tool.name,
  tool_version: 1 as const,
  arguments: args,
};
```

### Task 3: Upgrade the service app and destructively migrate storage

**Files:**
- Modify: `services/agent-service/tests/memory.test.ts`
- Modify: `services/agent-service/tests/app.test.ts`
- Modify: `services/agent-service/src/memory.ts`
- Modify: `services/agent-service/src/app.ts`
- Modify: `services/agent-service/src/server.ts`

- [ ] Add RED memory tests that populate every data table in a pre-v2 database, reopen it as v2, and assert all data is empty and `PRAGMA user_version` equals 2; also assert reopening a v2 database preserves new data.
- [ ] Add RED app tests that expect health/SSE envelopes v2, cache an `actions` decision, record ordered action names, and accept an outcome containing `action_id`.
- [ ] Add a checkpoint cleanup test using a temporary configured root containing `.sqlite`, `.sqlite-wal`, `.sqlite-shm`, and `keep.txt`; assert migration removes only SQLite checkpoint files.
- [ ] Run `npm test` and confirm RED on protocol version, old decision payload, and absent migration behavior.
- [ ] Make `MemoryRepository` expose whether initialization upgraded pre-v2 storage. For an existing database with `user_version != 2`, transactionally drop/recreate all Agent tables and FTS data, set `user_version = 2`, and report the upgrade. New missing database files initialize directly without reporting destructive upgrade.
- [ ] Add a focused exported cleanup function that resolves entries inside `checkpointRoot` and removes only `.sqlite`, `.sqlite-wal`, and `.sqlite-shm`. Call it from `server.ts` only when the repository reports a pre-v2 upgrade, before `listen()`.
- [ ] Update `app.ts` to advertise/write v2, cache action batches, store ordered action names in decision events, and parse v2 per-action outcomes.
- [ ] Run `npm test` and confirm all service tests pass.
- [ ] Commit with `git commit -m "feat: migrate Agent service storage to v2"`.

### Task 4: Parse and validate v2 batches in Godot

**Files:**
- Modify: `tests/test_agent_action_execution.gd`
- Modify: `tests/test_agent_streaming.gd`
- Modify: `scripts/ai_agent/agent_protocol.gd`
- Modify: `scripts/ai_agent/agent_action_validator.gd`
- Modify: `scripts/ai_agent/agent_sse_parser.gd`

- [ ] Replace test helpers with v2 batch envelopes. Add RED assertions for empty, one, three, and four actions; v1 rejection; duplicate IDs/keys; wait exclusivity; invalid nested arguments; and an old `expected_revision` passing validation.
- [ ] Update SSE tests to require version 2 and explicitly reject a version 1 event envelope.
- [ ] Run the Godot Agent suite and confirm RED because existing code expects v1 single actions and stale revisions reject.
- [ ] Set `AgentProtocol.PROTOCOL_VERSION = 2`; parse strict batch fields and return a deep-copied normalized envelope. Make requests use v2.
- [ ] Change `AgentActionValidator` to validate every action and remove only the equality comparison between `expected_revision` and current revision. Keep numeric revision validation in the protocol parser.
- [ ] Set the SSE envelope requirement to v2.
- [ ] Run the Godot Agent suite and confirm the parsing/validation tests pass, while executor tests remain RED until Task 5.
- [ ] Commit with `git commit -m "feat: validate Agent v2 action batches"`.

### Task 5: Execute v2 actions sequentially against current state

**Files:**
- Modify: `tests/test_agent_action_execution.gd`
- Modify: `tests/test_agent_main_integration.gd`
- Modify: `scripts/ai_agent/agent_action_executor_router.gd`
- Modify: `scripts/ai_agent/agent_runtime.gd`

- [ ] Add RED execution tests proving: empty batches return no outcomes; three current-state actions commit in order; stale expected revision does not reject; a conflicting second action returns a domain error and stops the third; travel/build `in_progress` stops the next action; replay uses stored per-action outcomes without duplication.
- [ ] Add a runtime integration assertion that every attempted action outcome is reported/published in order and an empty batch makes no extra Gateway request.
- [ ] Run the Godot Agent suite and confirm RED on missing batch execution.
- [ ] Refactor the existing `execute()` body into a private per-action executor, removing its revision equality check. Add `execute_batch(intent, game_minute) -> Array[Dictionary]` that traverses actions, appends outcomes, and stops on `rejected`, `failed`, or `in_progress`.
- [ ] Include `protocol_version: 2` and `action_id` in immediate, failure, and completed-activity outcomes. Keep one revision increment per successful mutation.
- [ ] Change `AgentRuntime._handle_response()` to execute the batch, publish each successful message, publish one warning for the first failed outcome, report each attempted outcome, and emit envelope speech once. Empty actions complete without reporting an outcome.
- [ ] Run the Godot Agent suite and headless startup; confirm GREEN with no parse/runtime errors.
- [ ] Commit with `git commit -m "feat: execute Agent v2 action batches"`.

### Task 6: Connected v2 acceptance and destructive local migration

**Files:**
- Modify: `tests/agent_service_integration.gd`
- Modify: `docs/validation/role-agent-framework-validation.md`
- Verify: configured Agent Service database and checkpoint root

- [ ] Update the connected acceptance runner to configure stream epoch v2, require health v2, validate an action array of length `0..3`, and submit one synthetic v2 outcome only when at least one action exists.
- [ ] Run fresh verification: `npm test`, Godot Agent suite, and headless startup. Record exact check counts.
- [ ] Stop the currently running local Agent Service, inspect and record the configured database/checkpoint paths without printing credentials, start the updated service, and verify the one-time migration cleared old table rows and checkpoint SQLite files.
- [ ] Run `godot_console --headless --path . --script res://tests/agent_service_integration.gd` against the restarted service and confirm the real Provider returns a valid v2 empty-or-one-to-three action decision.
- [ ] Update validation documentation with commands, counts, v2 migration evidence, and connected result; never include API keys or local configuration contents.
- [ ] Run `git diff --check` and `git status --short --branch`; commit with `git commit -m "test: validate Agent protocol v2 workflow"`.
